///|
test "policy JSON round trip retains signed scopes order defaults and decisions" {
  let source =
    #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":0.3},{"kind":"max_drop","metric":"ar100","threshold":0.05,"category_id":-7}]}
  let policy = @moondeteval.GatePolicy::from_json_string(source)
  assert_eq(policy.undefined_policy(), "fail")
  assert_eq(policy.rules()[1].category_id(), Some(-7))
  let encoded = policy.to_json_string()
  assert_true(encoded.contains("\"category_id\":null"))
  assert_eq(
    @moondeteval.GatePolicy::from_json_string(encoded).to_json_string(),
    encoded,
  )
  let (dataset, base, candidate) = gate_inputs()
  let pair = @moondeteval.compare_predictions(dataset, base, candidate)
  let file_result = pair.check_gates(policy)
  let direct = pair.check_gates(
    @moondeteval.GatePolicy::new([
      @moondeteval.GateRule::minimum("ap", 0.3),
      @moondeteval.GateRule::max_drop("ar100", 0.05, category_id=-7),
    ]),
  )
  assert_eq(file_result.to_json_string(), direct.to_json_string())
}

///|
test "policy JSON rejects unknown fields kinds versions and invalid numeric types" {
  for
    source in [
      "{",
      "[]",
      "{}",
      (
        #|{"format_version":1,"rules":[]}
      ),
      (
        #|{"format_version":"2","rules":[]}
      ),
      (
        #|{"format_version":"1","rule":[]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"min","metric":"ap","threshold":0}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":"0"}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":true}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":0,"category_id":1.5}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":0,"category_id":2147483648}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":0,"category_id":"7"}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":0,"catgory_id":7}]}
      ),
      (
        #|{"format_version":"1","undefined_policy":null,"rules":[{"kind":"minimum","metric":"ap","threshold":0}]}
      ),
      (
        #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":1e999}]}
      ),
    ] {
    try @moondeteval.GatePolicy::from_json_string(source) catch {
      @moondeteval.InvalidConfig(_) => ()
      _ => fail("wrong policy error")
    } noraise {
      _ => fail("invalid policy accepted: " + source)
    }
  }
}

///|
test "policy JSON delegates duplicates limits and undefined choices to shared policy" {
  let rule = @moondeteval.GateRule::minimum("ap_small", 0.0)
  let json = @moondeteval.GatePolicy::new([rule], undefined_policy="skip").to_json()
  let policy = @moondeteval.GatePolicy::from_json_string(json.stringify())
  assert_eq(policy.undefined_policy(), "skip")
  let duplicate =
    #|{"format_version":"1","rules":[{"kind":"minimum","metric":"ap","threshold":0},{"kind":"minimum","metric":"ap","threshold":0.5,"category_id":null}]}
  try @moondeteval.GatePolicy::from_json_string(duplicate) catch {
    @moondeteval.InvalidConfig(_) => ()
    _ => fail("wrong duplicate error")
  } noraise {
    _ => fail("duplicate accepted")
  }
  let many : Array[@moondeteval.GateRule] = []
  for id in 0..<1000 {
    many.push(@moondeteval.GateRule::minimum("ap", 0.0, category_id=id))
  }
  let round_trip = @moondeteval.GatePolicy::from_json_string(
    @moondeteval.GatePolicy::new(many).to_json_string(),
  )
  assert_eq(round_trip.rules().length(), 1000)
}
