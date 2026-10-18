///|
test "consumer checks overall and signed category regression through public gate API" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20)],
    [@moondeteval.Category::new(-9, "object")],
    [@moondeteval.GroundTruth::new(1L, 1, -9, box, area=100.0)],
  )
  let pair = @moondeteval.compare_predictions(
    dataset,
    [@moondeteval.Detection::new(1, 1, -9, box, 0.9)],
    [],
  )
  let result = pair.check_gates(
    @moondeteval.GatePolicy::new([
      @moondeteval.GateRule::minimum("ap", 0.0),
      @moondeteval.GateRule::max_drop("ap", 0.1, category_id=-9),
    ]),
  )
  assert_eq(result.status(), "failed")
  assert_eq(result.checks()[0].status(), "passed")
  assert_eq(result.checks()[1].drop(), Some(1.0))
  assert_eq(result.checks()[1].reason(), "drop_exceeded")
  assert_true(result.to_json_string().contains("\"format_version\":\"1\""))
}

///|
test "consumer evaluates a polygon mask then applies category and undefined rules" {
  let mask = @moondeteval.CocoRle::from_polygons(4, 4, [
    [0.0, 0.0, 3.0, 0.0, 3.0, 3.0, 0.0, 3.0],
  ])
  let dataset = @moondeteval.MaskDataset::new(
    [@moondeteval.Image::new(1, 4, 4)],
    [@moondeteval.Category::new(85, "object")],
    [@moondeteval.MaskGroundTruth::new(1L, 1, 85, mask, area=9.0)],
  )
  let report = @moondeteval.evaluate_masks(dataset, [
    @moondeteval.MaskDetection::new(1, 1, 85, mask, 0.8),
  ])
  let result = report.check_gates(
    @moondeteval.GatePolicy::new(
      [
        @moondeteval.GateRule::minimum("ap", 1.0, category_id=85),
        @moondeteval.GateRule::minimum("ap_large", 0.0),
      ],
      undefined_policy="skip",
    ),
  )
  assert_eq(result.status(), "passed")
  assert_eq(result.checks()[1].status(), "skipped")
  assert_eq(result.checks()[1].candidate(), None)
}
