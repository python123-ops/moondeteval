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
    include_pr_curves=true,
  )
  let result = @moondeteval.compare_predictions_with_config(
    dataset, baseline, candidate, config,
  )
  assert_eq(result.baseline().summary().ap50(), 1.0)
  assert_eq(result.candidate().summary().ap50(), 0.5)
  assert_eq(result.metrics().length(), 12)
  let names = [
    "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large", "ar1", "ar10", "ar100",
    "ar_small", "ar_medium", "ar_large",
  ]
  for index in 0..<names.length() {
    assert_eq(result.metrics()[index].name(), names[index])
    assert_eq(result.classes()[0].metrics()[index].name(), names[index])
  }
  assert_eq(result.metrics()[1].name(), "ap50")
  assert_eq(result.metrics()[1].baseline(), Some(1.0))
  assert_eq(result.metrics()[1].candidate(), Some(0.5))
  assert_eq(result.metrics()[1].delta(), Some(-0.5))
  assert_eq(result.classes()[1].category_id(), 2)
  assert_eq(result.classes()[1].metrics()[1].delta(), None)
  assert_eq(result.baseline().diagnostics()[0].status(), "tp")
  assert_eq(result.candidate().diagnostics()[0].status(), "fp")
  assert_eq(result.baseline().pr_curves().length(), 4)
  assert_eq(result.candidate().pr_curves().length(), 4)
  assert_eq(result.baseline().pr_curves()[0].ap(), 1.0)
  assert_eq(result.candidate().pr_curves()[0].ap(), 0.5)
  assert_eq(result.candidate().pr_curves()[2].ap(), -1.0)
  assert_true(result.to_json_string().contains("\"delta\":null"))
  assert_true(result.to_json_string().contains("\"schema_version\":\"0.1.0\""))
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

///|
test "image ranking isolates regressions at IoU 0.50 without full diagnostics" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let far = @moondeteval.Box::from_xywh(30.0, 30.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [
      @moondeteval.Image::new(3, 50, 50),
      @moondeteval.Image::new(1, 50, 50),
      @moondeteval.Image::new(2, 50, 50),
      @moondeteval.Image::new(4, 50, 50),
    ],
    [@moondeteval.Category::new(7, "object")],
    [
      @moondeteval.GroundTruth::new(1, 1, 7, box, area=100.0),
      @moondeteval.GroundTruth::new(2, 2, 7, box, area=100.0),
    ],
  )
  let baseline = [
    @moondeteval.Detection::new(1, 1, 7, box, 0.9),
    @moondeteval.Detection::new(2, 2, 7, box, 0.9),
    @moondeteval.Detection::new(5, 2, 7, far, 0.8),
  ]
  let candidate = [
    @moondeteval.Detection::new(3, 2, 7, box, 0.9),
    @moondeteval.Detection::new(4, 3, 7, far, 0.9),
  ]
  let config = @moondeteval.EvalConfig::new(
    [0.75],
    include_image_summaries=true,
  )
  let comparison = @moondeteval.compare_predictions_with_config(
    dataset, baseline, candidate, config,
  )
  let changes = comparison.image_changes()
  assert_eq(changes.length(), 4)
  assert_eq(changes[0].image_id(), 1)
  assert_eq(changes[0].error_delta(), 1)
  assert_eq(changes[1].image_id(), 3)
  assert_eq(changes[1].error_delta(), 1)
  assert_eq(changes[2].image_id(), 4)
  assert_eq(changes[2].error_delta(), 0)
  assert_eq(changes[3].image_id(), 2)
  assert_eq(changes[3].error_delta(), -1)
  let summaries = comparison.candidate().image_summaries()
  assert_eq(summaries[0].image_id(), 1)
  assert_eq(summaries[0].fn_count(), 1)
  assert_eq(summaries[1].tp(), 1)
  assert_eq(summaries[2].fp(), 1)
  assert_eq(summaries[3].image_id(), 4)
  assert_eq(summaries[3].tp(), 0)
  assert_eq(summaries[3].fn_count(), 0)
  assert_eq(comparison.candidate().diagnostics().length(), 0)
  assert_eq(comparison.candidate().summary().ap50(), 51.0 / 101.0)
  assert_true(comparison.to_json_string().contains("\"error_delta\":1"))
}
