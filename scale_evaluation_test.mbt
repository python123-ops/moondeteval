///|
test "mask cache budgets preserve full reports with crowd ignore area and custom thresholds" {
  let a = @moondeteval.CocoRle::new(2, 2, [0, 1, 2, 1])
  let b = @moondeteval.CocoRle::new(2, 2, [1, 2, 1])
  let full = @moondeteval.CocoRle::new(2, 2, [0, 4])
  let dataset = @moondeteval.MaskDataset::new(
    [
      @moondeteval.Image::new(-9, 2, 2),
      @moondeteval.Image::new(13, 2, 2),
      @moondeteval.Image::new(77, 2, 2),
    ],
    [@moondeteval.Category::new(-7, "a"), @moondeteval.Category::new(85, "b")],
    [
      @moondeteval.MaskGroundTruth::new(
        9L,
        -9,
        -7,
        full,
        area=9216.0,
        iscrowd=true,
      ),
      @moondeteval.MaskGroundTruth::new(3L, -9, -7, a, area=1024.0),
      @moondeteval.MaskGroundTruth::new(
        7L,
        -9,
        -7,
        b,
        area=10000.0,
        ignore=true,
      ),
      @moondeteval.MaskGroundTruth::new(8L, 13, -7, b, area=2.0),
    ],
  )
  let predictions = [
    @moondeteval.MaskDetection::new(0, -9, -7, a, 0.9),
    @moondeteval.MaskDetection::new(1, -9, -7, a, 0.9),
    @moondeteval.MaskDetection::new(2, -9, 85, a, 0.8),
    @moondeteval.MaskDetection::new(3, 13, -7, b, 0.7),
    @moondeteval.MaskDetection::new(4, 77, -7, a, 0.6),
  ]
  for policy in ["coco_segm", "respect_explicit"] {
    let config = @moondeteval.EvalConfig::new(
      [0.55, 0.85],
      include_diagnostics=true,
      include_image_summaries=true,
      include_pr_curves=true,
      ignore_policy=policy,
    )
    let reference = @moondeteval.evaluate_masks_with_config(
      dataset,
      predictions,
      config,
      max_iou_cache_pairs=0,
    ).to_json_string()
    for budget in [1, 5, 6, 7, 1000, 16777216] {
      let actual = @moondeteval.evaluate_masks_with_config(
        dataset,
        predictions,
        config,
        max_iou_cache_pairs=budget,
      )
      assert_eq(actual.to_json_string(), reference)
    }
    let paired = @moondeteval.compare_mask_predictions_with_config(
      dataset,
      predictions,
      [],
      config,
      max_iou_cache_pairs=0,
    ).to_json_string()
    assert_eq(
      @moondeteval.compare_mask_predictions_with_config(
        dataset,
        predictions,
        [],
        config,
      ).to_json_string(),
      paired,
    )
  }
}

///|
test "sparse grouping preserves empty images undefined classes and cross-class diagnostics" {
  let mask = @moondeteval.CocoRle::new(2, 2, [0, 4])
  let dataset = @moondeteval.MaskDataset::new(
    [
      @moondeteval.Image::new(1, 2, 2),
      @moondeteval.Image::new(2, 2, 2),
      @moondeteval.Image::new(3, 2, 2),
    ],
    [
      @moondeteval.Category::new(1, "truth"),
      @moondeteval.Category::new(2, "prediction"),
      @moondeteval.Category::new(3, "empty"),
    ],
    [@moondeteval.MaskGroundTruth::new(1L, 1, 1, mask, area=4.0)],
  )
  let config = @moondeteval.EvalConfig::new(
    [0.5],
    include_diagnostics=true,
    include_image_summaries=true,
  )
  let report = @moondeteval.evaluate_masks_with_config(
    dataset,
    [@moondeteval.MaskDetection::new(1, 1, 2, mask, 0.9)],
    config,
  )
  assert_eq(report.counts().images(), 3)
  assert_eq(report.image_summaries().length(), 3)
  assert_eq(report.image_summaries()[2].fp(), 0)
  assert_eq(report.classes()[2].metrics().ap(), -1.0)
  assert_true(
    report.diagnostics().any(entry => entry.reason() == "wrong_class"),
  )
}

///|
test "mask cache validates limits and does not truncate input counts at rank one hundred" {
  let mask = @moondeteval.CocoRle::new(2, 2, [0, 4])
  let dataset = mask_dataset(mask, area=4.0)
  let predictions = Array::makei(101, index => {
    @moondeteval.MaskDetection::new(index, 1, 1, mask, 0.9)
  })
  let config = @moondeteval.EvalConfig::coco()
  let report = @moondeteval.evaluate_masks_with_config(
    dataset,
    predictions,
    config,
    max_iou_cache_pairs=100,
  )
  assert_eq(report.counts().detections(), 101)
  assert_eq(report.counts().evaluated_detections(), 100)
  assert_eq(
    report.to_json_string(),
    @moondeteval.evaluate_masks_with_config(
      dataset,
      predictions,
      config,
      max_iou_cache_pairs=0,
    ).to_json_string(),
  )
  for limit in [-1, 16777217] {
    try
      @moondeteval.evaluate_masks_with_config(
        dataset,
        predictions,
        config,
        max_iou_cache_pairs=limit,
      )
    catch {
      @moondeteval.InvalidConfig(_) => ()
      _ => fail("wrong resource error")
    } noraise {
      _ => fail("invalid cache limit accepted")
    }
  }
}
