///|
test "paired comparison reports twelve deltas and undefined class values" {
  let target = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let background = @moondeteval.Box::from_xywh(50.0, 50.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [
      @moondeteval.Category::new(1, "present"),
      @moondeteval.Category::new(2, "empty"),
    ],
    [@moondeteval.GroundTruth::new(1, 1, 1, target, area=400.0)],
  )
  let baseline = [@moondeteval.Detection::new(10, 1, 1, target, 0.9)]
  let candidate = [
    @moondeteval.Detection::new(20, 1, 1, background, 0.9),
    @moondeteval.Detection::new(21, 1, 1, target, 0.8),
  ]
  let config = @moondeteval.EvalConfig::new(
    [0.5, 0.75],
    include_diagnostics=true,
  )
  let result = @moondeteval.compare_predictions_with_config(
    dataset, baseline, candidate, config,
  )
  assert_eq(result.baseline().summary().ap50(), 1.0)
  assert_eq(result.candidate().summary().ap50(), 0.5)
  assert_eq(result.metrics().length(), 12)
  assert_eq(result.metrics()[1].name(), "ap50")
  assert_eq(result.metrics()[1].baseline(), Some(1.0))
  assert_eq(result.metrics()[1].candidate(), Some(0.5))
  assert_eq(result.metrics()[1].delta(), Some(-0.5))
  assert_eq(result.classes()[1].category_id(), 2)
  assert_eq(result.classes()[1].metrics()[1].delta(), None)
  assert_eq(result.baseline().diagnostics()[0].status(), "tp")
  assert_eq(result.candidate().diagnostics()[0].status(), "fp")
  assert_true(result.to_json_string().contains("\"delta\":null"))
}

///|
test "comparison defaults are identical to two standalone evaluations" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 1, box, area=100.0)],
  )
  let baseline = [@moondeteval.Detection::new(1, 1, 1, box, 0.9)]
  let comparison = @moondeteval.compare_predictions(dataset, baseline, [])
  assert_eq(
    comparison.baseline().summary().ap(),
    @moondeteval.evaluate(dataset, baseline).summary().ap(),
  )
  assert_eq(
    comparison.candidate().summary().ap(),
    @moondeteval.evaluate(dataset, []).summary().ap(),
  )
  assert_eq(comparison.metrics()[0].delta(), Some(-1.0))
}
