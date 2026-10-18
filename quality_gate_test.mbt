///|
fn gate_inputs(
  empty~ : Bool = false,
  crowd~ : Bool = false,
) -> (
  @moondeteval.Dataset,
  Array[@moondeteval.Detection],
  Array[@moondeteval.Detection],
) raise {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let wrong = @moondeteval.Box::from_xywh(20.0, 20.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [
      @moondeteval.Category::new(-7, "present"),
      @moondeteval.Category::new(85, "empty"),
    ],
    if empty {
      []
    } else {
      [@moondeteval.GroundTruth::new(1L, 1, -7, box, area=100.0, iscrowd=crowd)]
    },
  )
  let good = @moondeteval.Detection::new(1, 1, -7, box, 0.8)
  (dataset, [good], [@moondeteval.Detection::new(2, 1, -7, wrong, 0.9), good])
}

///|
fn gate_error(action : () -> Unit raise @moondeteval.EvalError) -> Unit raise {
  try action() catch {
    @moondeteval.InvalidConfig(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("invalid gate configuration accepted")
  }
}

///|
test "gates support all twelve metrics without changing evaluation output" {
  let (dataset, base, candidate) = gate_inputs()
  let pair = @moondeteval.compare_predictions(dataset, base, candidate)
  let before = pair.to_json_string()
  let rules = [
    "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large", "ar1", "ar10", "ar100",
    "ar_small", "ar_medium", "ar_large",
  ].map(name => @moondeteval.GateRule::minimum(name, 0.0))
  let checked = pair.check_gates(
    @moondeteval.GatePolicy::new(rules, undefined_policy="skip"),
  )
  assert_eq(checked.status(), "passed")
  assert_eq(checked.checks().length(), 12)
  assert_eq(checked.checks()[0].candidate(), Some(0.5))
  assert_eq(pair.to_json_string(), before)
}

///|
test "gate equality and tolerance are inclusive for minima and drops" {
  let (dataset, base, candidate) = gate_inputs()
  let pair = @moondeteval.compare_predictions(dataset, base, candidate)
  for
    (threshold, expected) in [
      (0.5, "passed"),
      (0.5 + 5.0e-13, "passed"),
      (0.5 + 2.0e-12, "failed"),
    ] {
    assert_eq(
      pair
      .check_gates(
        @moondeteval.GatePolicy::new([
          @moondeteval.GateRule::minimum("ap50", threshold),
        ]),
      )
      .status(),
      expected,
    )
  }
  for
    (threshold, expected) in [
      (0.5, "passed"),
      (0.5 - 5.0e-13, "passed"),
      (0.5 - 2.0e-12, "failed"),
    ] {
    assert_eq(
      pair
      .check_gates(
        @moondeteval.GatePolicy::new([
          @moondeteval.GateRule::max_drop("ap50", threshold),
        ]),
      )
      .status(),
      expected,
    )
  }
}

///|
test "zero allowed drop accepts equality and improvements but rejects regression" {
  let (dataset, base, candidate) = gate_inputs()
  let policy = @moondeteval.GatePolicy::new([
    @moondeteval.GateRule::max_drop("ap", 0.0),
  ])
  assert_eq(
    @moondeteval.compare_predictions(dataset, base, base)
    .check_gates(policy)
    .status(),
    "passed",
  )
  let improvement = @moondeteval.compare_predictions(dataset, candidate, base).check_gates(
    policy,
  )
  assert_eq(improvement.status(), "passed")
  assert_eq(improvement.checks()[0].drop(), Some(-0.5))
  assert_eq(
    @moondeteval.compare_predictions(dataset, base, candidate)
    .check_gates(policy)
    .status(),
    "failed",
  )
}

///|
test "overall success cannot hide failure of a signed non-contiguous category" {
  let (dataset, base, candidate) = gate_inputs()
  let checked = @moondeteval.compare_predictions(dataset, base, candidate).check_gates(
    @moondeteval.GatePolicy::new([
      @moondeteval.GateRule::minimum("ap", 0.4),
      @moondeteval.GateRule::minimum("ap", 0.6, category_id=-7),
      @moondeteval.GateRule::max_drop("ar100", 0.0),
    ]),
  )
  assert_eq(checked.status(), "failed")
  assert_eq(checked.checks()[0].status(), "passed")
  assert_eq(checked.checks()[1].status(), "failed")
  assert_eq(checked.checks()[1].reason(), "below_minimum")
  assert_eq(checked.checks()[1].category_id(), Some(-7))
  assert_eq(checked.checks()[2].status(), "passed")
}

///|
test "undefined gates fail by default and all skipped never pass" {
  let (dataset, base, _) = gate_inputs()
  let report = @moondeteval.evaluate(dataset, base)
  let missing = @moondeteval.GateRule::minimum("ap", 0.0, category_id=85)
  let failed = report.check_gates(@moondeteval.GatePolicy::new([missing]))
  assert_eq(failed.status(), "failed")
  assert_eq(failed.checks()[0].candidate(), None)
  assert_true(failed.to_json_string().contains("\"candidate\":null"))
  let skipped = report.check_gates(
    @moondeteval.GatePolicy::new([missing], undefined_policy="skip"),
  )
  assert_eq(skipped.status(), "failed")
  assert_eq(skipped.reason(), "all_skipped")
  assert_eq(skipped.checks()[0].status(), "skipped")
  let mixed = report.check_gates(
    @moondeteval.GatePolicy::new(
      [missing, @moondeteval.GateRule::minimum("ap", 0.9)],
      undefined_policy="skip",
    ),
  )
  assert_eq(mixed.status(), "passed")
}

///|
test "unknown category and drop on a single report are configuration errors" {
  let (dataset, base, _) = gate_inputs()
  let report = @moondeteval.evaluate(dataset, base)
  gate_error(() => {
    ignore(
      report.check_gates(
        @moondeteval.GatePolicy::new(
          [@moondeteval.GateRule::minimum("ap", 0.0, category_id=86)],
          undefined_policy="skip",
        ),
      ),
    )
  })
  gate_error(() => {
    ignore(
      report.check_gates(
        @moondeteval.GatePolicy::new([
          @moondeteval.GateRule::max_drop("ap", 0.1),
        ]),
      ),
    )
  })
}

///|
test "no predictions is defined zero whereas empty and crowd-only truth is undefined" {
  let (dataset, _, _) = gate_inputs()
  let policy = @moondeteval.GatePolicy::new([
    @moondeteval.GateRule::minimum("ap", 0.0),
  ])
  let zero = @moondeteval.evaluate(dataset, []).check_gates(policy)
  assert_eq(zero.status(), "passed")
  assert_eq(zero.checks()[0].candidate(), Some(0.0))
  for (empty, crowd) in [(true, false), (false, true)] {
    let (dataset, predictions, _) = gate_inputs(empty~, crowd~)
    let checked = @moondeteval.evaluate(dataset, predictions).check_gates(
      policy,
    )
    assert_eq(checked.status(), "failed")
    assert_eq(checked.checks()[0].reason(), "undefined_candidate")
  }
}

///|
test "gate constructors reject unknown metrics nonfinite and out-of-range thresholds" {
  gate_error(() => ignore(@moondeteval.GateRule::minimum("accuracy", 0.5)))
  for value in [-0.01, 1.01, @double.not_a_number, @double.infinity] {
    gate_error(() => ignore(@moondeteval.GateRule::minimum("ap", value)))
    gate_error(() => ignore(@moondeteval.GateRule::max_drop("ap", value)))
  }
}

///|
test "gate policies reject duplicate empty oversized and unknown undefined policies" {
  let rule = @moondeteval.GateRule::minimum("ap", 0.1)
  gate_error(() => ignore(@moondeteval.GatePolicy::new([])))
  gate_error(() => ignore(@moondeteval.GatePolicy::new([rule, rule])))
  gate_error(() => {
    ignore(@moondeteval.GatePolicy::new([rule], undefined_policy="ignore"))
  })
  let many : Array[@moondeteval.GateRule] = []
  for id in 0..<1000 {
    many.push(@moondeteval.GateRule::minimum("ap", 0.0, category_id=id))
  }
  assert_eq(@moondeteval.GatePolicy::new(many).rules().length(), 1000)
  many.push(@moondeteval.GateRule::minimum("ap", 0.0, category_id=1000))
  gate_error(() => ignore(@moondeteval.GatePolicy::new(many)))
}

///|
test "policy and gate report accessors make defensive copies" {
  let (dataset, base, _) = gate_inputs()
  let rule = @moondeteval.GateRule::minimum("ap", 0.9)
  let rules = [rule]
  let policy = @moondeteval.GatePolicy::new(rules)
  rules.clear()
  policy.rules().clear()
  assert_eq(policy.rules().length(), 1)
  let checked = @moondeteval.evaluate(dataset, base).check_gates(policy)
  checked.checks().clear()
  assert_eq(checked.checks().length(), 1)
  assert_eq(checked.undefined_policy(), "fail")
  assert_eq(rule.kind(), "minimum")
  assert_eq(rule.metric(), "ap")
  assert_eq(rule.threshold(), 0.9)
}

///|
test "mask comparisons use the same gate engine for pixels and category scope" {
  let mask = @moondeteval.CocoRle::new(2, 2, [0, 1, 2, 1])
  let other = @moondeteval.CocoRle::new(2, 2, [1, 2, 1])
  let dataset = @moondeteval.MaskDataset::new(
    [@moondeteval.Image::new(1, 2, 2)],
    [@moondeteval.Category::new(85, "object")],
    [@moondeteval.MaskGroundTruth::new(9L, 1, 85, mask, area=2.0)],
  )
  let result = @moondeteval.compare_mask_predictions(
    dataset,
    [@moondeteval.MaskDetection::new(0, 1, 85, other, 0.9)],
    [@moondeteval.MaskDetection::new(0, 1, 85, mask, 0.9)],
  ).check_gates(
    @moondeteval.GatePolicy::new([
      @moondeteval.GateRule::minimum("ap", 1.0, category_id=85),
      @moondeteval.GateRule::max_drop("ap", 0.0),
    ]),
  )
  assert_eq(result.status(), "passed")
  assert_eq(result.checks()[1].baseline(), Some(0.0))
  assert_eq(result.checks()[1].candidate(), Some(1.0))
  assert_eq(result.checks()[1].drop(), Some(-1.0))
}
