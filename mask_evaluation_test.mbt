///|
fn mask_dataset(
  mask : @moondeteval.CocoRle,
  area? : Double = 2.0,
  crowd? : Bool = false,
  ignore? : Bool = false,
) -> @moondeteval.MaskDataset raise @moondeteval.EvalError {
  @moondeteval.MaskDataset::new(
    [@moondeteval.Image::new(1, mask.width(), mask.height())],
    [@moondeteval.Category::new(1, "object")],
    [
      @moondeteval.MaskGroundTruth::new(
        7,
        1,
        1,
        mask,
        area~,
        iscrowd=crowd,
        ignore~,
      ),
    ],
  )
}

///|
test "mask AP uses pixels when two masks share the same bounding box" {
  let truth = @moondeteval.CocoRle::new(2, 2, [0, 1, 2, 1])
  let wrong = @moondeteval.CocoRle::new(2, 2, [1, 2, 1])
  let dataset = mask_dataset(truth)
  let good = @moondeteval.MaskDetection::new(0, 1, 1, truth, 0.8)
  let bad = @moondeteval.MaskDetection::new(0, 1, 1, wrong, 0.8)
  assert_eq(@moondeteval.evaluate_masks(dataset, [bad]).summary().ap(), 0.0)
  let config = @moondeteval.EvalConfig::new(
    @moondeteval.EvalConfig::coco().iou_thresholds(),
    include_diagnostics=true,
    include_image_summaries=true,
    include_pr_curves=true,
  )
  let comparison = @moondeteval.compare_mask_predictions_with_config(
    dataset,
    [bad],
    [good],
    config,
  )
  assert_eq(comparison.candidate().summary().ap(), 1.0)
  assert_eq(comparison.candidate().config().ignore_policy(), "coco_segm")
  assert_eq(comparison.candidate().iou_type(), "segm")
  assert_eq(comparison.image_changes()[0].error_delta(), -2)
  assert_eq(comparison.metrics()[0].delta(), Some(1.0))
  assert_eq(comparison.candidate().pr_curves().length(), 10)
  assert_eq(comparison.candidate().pr_curves()[0].precision().length(), 101)
  assert_true(comparison.to_json_string().contains("\"iou_type\":\"segm\""))
}

///|
test "mask crowd repeated containment uses detection area and prefers regular truth" {
  let full = @moondeteval.CocoRle::new(2, 2, [0, 4])
  let one = @moondeteval.CocoRle::new(2, 2, [0, 1, 3])
  let dataset = @moondeteval.MaskDataset::new(
    [@moondeteval.Image::new(1, 2, 2)],
    [@moondeteval.Category::new(1, "object")],
    [
      @moondeteval.MaskGroundTruth::new(1, 1, 1, full, area=4.0, iscrowd=true),
      @moondeteval.MaskGroundTruth::new(2, 1, 1, one, area=1.0),
    ],
  )
  let config = @moondeteval.EvalConfig::new([0.5], include_diagnostics=true)
  let report = @moondeteval.evaluate_masks_with_config(
    dataset,
    [
      @moondeteval.MaskDetection::new(0, 1, 1, one, 0.9),
      @moondeteval.MaskDetection::new(1, 1, 1, one, 0.8),
      @moondeteval.MaskDetection::new(2, 1, 1, one, 0.7),
    ],
    config,
  )
  assert_eq(report.summary().ap(), 1.0)
  assert_eq(report.diagnostics()[0].ground_truth_id(), Some(2L))
  assert_eq(report.diagnostics()[1].status(), "ignored")
  assert_eq(report.diagnostics()[1].iou(), 1.0)
  assert_eq(report.diagnostics()[2].reason(), "crowd")
}

///|
test "mask unmatched area filtering uses foreground not image canvas" {
  let one = @moondeteval.CocoRle::new(120, 120, [0, 1, 14399])
  let wrong = @moondeteval.CocoRle::new(120, 120, [1, 1, 14398])
  let report = @moondeteval.evaluate_masks(mask_dataset(one, area=1.0), [
    @moondeteval.MaskDetection::new(0, 1, 1, wrong, 0.9),
    @moondeteval.MaskDetection::new(1, 1, 1, one, 0.8),
  ])
  assert_eq(report.summary().ap_small(), 0.5)
  assert_eq(report.summary().ap_medium(), -1.0)
  assert_eq(report.summary().ar1(), 0.0)
  assert_eq(report.summary().ar10(), 1.0)
}

///|
test "mask GT annotation area is preserved including shared bin boundaries" {
  let one = @moondeteval.CocoRle::new(1, 1, [0, 1])
  let prediction = @moondeteval.MaskDetection::new(0, 1, 1, one, 0.9)
  let small_medium = @moondeteval.evaluate_masks(
    mask_dataset(one, area=1024.0),
    [prediction],
  )
  assert_eq(small_medium.summary().ap_small(), 1.0)
  assert_eq(small_medium.summary().ap_medium(), 1.0)
  assert_eq(small_medium.summary().ap_large(), -1.0)
  let medium_large = @moondeteval.evaluate_masks(
    mask_dataset(one, area=9216.0),
    [prediction],
  )
  assert_eq(medium_large.summary().ap_medium(), 1.0)
  assert_eq(medium_large.summary().ap_large(), 1.0)
}

///|
test "empty mask truth remains eligible and empty predictions cannot match" {
  let empty = @moondeteval.CocoRle::new(2, 2, [4])
  let report = @moondeteval.evaluate_masks(mask_dataset(empty, area=0.0), [
    @moondeteval.MaskDetection::new(0, 1, 1, empty, 1.0),
  ])
  assert_eq(report.summary().ap(), 0.0)
  assert_eq(report.summary().ar100(), 0.0)
  assert_eq(
    @moondeteval.evaluate_masks(mask_dataset(empty), []).summary().ap(),
    0.0,
  )
  assert_eq(
    @moondeteval.evaluate_masks(mask_dataset(empty, crowd=true), [])
    .summary()
    .ap(),
    -1.0,
  )
  let dataset = @moondeteval.MaskDataset::new(
    [],
    [@moondeteval.Category::new(1, "empty")],
    [],
  )
  assert_eq(@moondeteval.evaluate_masks(dataset, []).summary().ap(), -1.0)
}

///|
test "mask stable same score cutoff retains rank 100 but excludes rank 101" {
  let one = @moondeteval.CocoRle::new(1, 1, [0, 1])
  let empty = @moondeteval.CocoRle::new(1, 1, [1])
  let predictions : Array[@moondeteval.MaskDetection] = []
  for id in 0..<100 {
    predictions.push(@moondeteval.MaskDetection::new(id, 1, 1, empty, 0.5))
  }
  predictions.push(@moondeteval.MaskDetection::new(100, 1, 1, one, 0.5))
  assert_eq(
    @moondeteval.evaluate_masks(mask_dataset(one), predictions)
    .summary()
    .ar100(),
    0.0,
  )
  predictions[99] = @moondeteval.MaskDetection::new(99, 1, 1, one, 0.5)
  let report = @moondeteval.evaluate_masks(mask_dataset(one), predictions)
  assert_eq(report.summary().ar100(), 1.0)
  assert_true((report.summary().ap() - 0.01).abs() < 1.0e-12)
  assert_eq(report.counts().evaluated_detections(), 100)
}

///|
test "mask default COCO explicit ignore and opt in extension" {
  let one = @moondeteval.CocoRle::new(1, 1, [0, 1])
  let dataset = mask_dataset(one, ignore=true)
  let prediction = @moondeteval.MaskDetection::new(0, 1, 1, one, 1.0)
  assert_eq(
    @moondeteval.evaluate_masks(dataset, [prediction]).summary().ap(),
    1.0,
  )
  let config = @moondeteval.EvalConfig::new(
    [0.5],
    ignore_policy="respect_explicit",
  )
  assert_eq(
    @moondeteval.evaluate_masks_with_config(dataset, [prediction], config)
    .summary()
    .ap(),
    -1.0,
  )
}

///|
test "mask models reject canvas mismatch references duplicate ids and bad scores" {
  let one = @moondeteval.CocoRle::new(1, 1, [0, 1])
  let truth = @moondeteval.MaskGroundTruth::new(1, 1, 1, one, area=1.0)
  let result = try
    @moondeteval.MaskDataset::new(
      [@moondeteval.Image::new(1, 2, 2)],
      [@moondeteval.Category::new(1, "a")],
      [truth],
    )
  catch {
    error => {
      assert_true(error.message().contains("dimensions"))
      None
    }
  } noraise {
    _ => Some(1)
  }
  assert_eq(result, None)
  let dataset = mask_dataset(one)
  let wrong = @moondeteval.CocoRle::new(1, 2, [0, 2])
  for
    prediction in [
      @moondeteval.MaskDetection::new(0, 1, 1, wrong, 1.0),
      @moondeteval.MaskDetection::new(0, 2, 1, one, 1.0),
      @moondeteval.MaskDetection::new(0, 1, 2, one, 1.0),
    ] {
    let rejected = try
      @moondeteval.evaluate_masks(dataset, [prediction])
    catch {
      _ => true
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
  let same = @moondeteval.MaskDetection::new(0, 1, 1, one, 0.9)
  assert_true(
    try @moondeteval.evaluate_masks(dataset, [same, same]) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  assert_true(
    try @moondeteval.MaskDetection::new(0, 1, 1, one, 0.0 / 0.0) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
  let copy = dataset.truths()
  copy.clear()
  assert_eq(dataset.truths().length(), 1)
}

///|
test "mask COCO parsing preserves Int64 ids and ignores supplied prediction bbox area" {
  let gt = "{\"images\":[{\"id\":1,\"width\":1,\"height\":1}],\"categories\":[{\"id\":1,\"name\":\"a\"}],\"annotations\":[{\"id\":9007199254740993,\"image_id\":1,\"category_id\":1,\"area\":1,\"segmentation\":{\"size\":[1,1],\"counts\":[0,1]}}]}"
  let dataset = @moondeteval.parse_coco_mask_dataset(gt)
  let predictions = @moondeteval.parse_coco_mask_detections(
    "[{\"image_id\":1,\"category_id\":1,\"score\":0.9,\"bbox\":[0,0,999,999],\"area\":9999,\"segmentation\":{\"size\":[1,1],\"counts\":\"01\"}}]",
  )
  assert_eq(dataset.truths()[0].id(), 9007199254740993L)
  assert_eq(
    @moondeteval.evaluate_masks(dataset, predictions).summary().ap_small(),
    1.0,
  )
  assert_true(
    try
      @moondeteval.parse_coco_mask_detections(
        "[{\"image_id\":1,\"category_id\":1,\"score\":1,\"segmentation\":[[0,0,1,0,1,1]]}]",
      )
    catch {
      error => error.message().contains("detections[0]")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @moondeteval.parse_coco_mask_dataset(gt.replace(old="[1,1]", new="[1,2]"))
    catch {
      error => error.message().contains("annotations[0]")
    } noraise {
      _ => false
    },
  )
}

///|
test "mask custom thresholds fixed probes and replayable config" {
  let truth = @moondeteval.CocoRle::new(1, 10, [0, 10])
  let partial = @moondeteval.CocoRle::new(1, 10, [0, 6, 4])
  let config = @moondeteval.EvalConfig::new(
    [0.9],
    ignore_policy="coco_segm",
    include_pr_curves=true,
  )
  let report = @moondeteval.evaluate_masks_with_config(
    mask_dataset(truth, area=10.0),
    [@moondeteval.MaskDetection::new(0, 1, 1, partial, 1.0)],
    config,
  )
  assert_eq(report.summary().ap(), 0.0)
  assert_eq(report.summary().ap50(), 1.0)
  assert_eq(report.summary().ap75(), 0.0)
  assert_eq(report.pr_curves().length(), 1)
  let bbox = @moondeteval.Dataset::new([], [], [])
  assert_true(
    try @moondeteval.evaluate_with_config(bbox, [], config) catch {
      _ => true
    } noraise {
      _ => false
    },
  )
}

///|
test "mask diagnostic reasons use mask geometry across categories" {
  let exact = @moondeteval.CocoRle::new(1, 10, [0, 5, 5])
  let localized = @moondeteval.CocoRle::new(1, 10, [4, 5, 1])
  let empty = @moondeteval.CocoRle::new(1, 10, [10])
  let dataset = @moondeteval.MaskDataset::new(
    [@moondeteval.Image::new(1, 10, 1)],
    [@moondeteval.Category::new(1, "a"), @moondeteval.Category::new(2, "b")],
    [@moondeteval.MaskGroundTruth::new(1, 1, 1, exact, area=5.0)],
  )
  let config = @moondeteval.EvalConfig::new([0.5], include_diagnostics=true)
  let report = @moondeteval.evaluate_masks_with_config(
    dataset,
    [
      @moondeteval.MaskDetection::new(0, 1, 1, exact, 1.0),
      @moondeteval.MaskDetection::new(1, 1, 1, exact, 0.9),
      @moondeteval.MaskDetection::new(2, 1, 1, localized, 0.8),
      @moondeteval.MaskDetection::new(3, 1, 1, empty, 0.7),
      @moondeteval.MaskDetection::new(4, 1, 2, exact, 0.6),
    ],
    config,
  )
  assert_eq(report.diagnostics()[1].reason(), "duplicate")
  assert_eq(report.diagnostics()[2].reason(), "localization")
  assert_eq(report.diagnostics()[3].reason(), "background")
  assert_eq(report.diagnostics()[4].reason(), "wrong_class")
}
