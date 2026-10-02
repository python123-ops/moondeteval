///|
test "perfect detection gives AP and AR of one" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(10, 100, 100)],
    [@moondeteval.Category::new(7, "object")],
    [@moondeteval.GroundTruth::new(91, 10, 7, box, area=400.0)],
  )
  let prediction = @moondeteval.Detection::new(1, 10, 7, box, 0.9)
  let result = @moondeteval.evaluate(dataset, [prediction])
  assert_true(result.summary().ap() > 0.999999)
  assert_eq(result.summary().ar1(), 1.0)
  assert_eq(result.summary().ap_medium(), -1.0)
  assert_eq(result.classes()[0].category_id(), 7)
}

///|
test "report counts inputs and retained detections per image and category" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20), @moondeteval.Image::new(2, 20, 20)],
    [@moondeteval.Category::new(1, "a"), @moondeteval.Category::new(2, "b")],
    [@moondeteval.GroundTruth::new(1, 1, 1, box, area=100.0)],
  )
  let detections : Array[@moondeteval.Detection] = []
  for id in 0..<105 {
    detections.push(@moondeteval.Detection::new(id, 1, 1, box, 0.5))
  }
  detections.push(@moondeteval.Detection::new(105, 1, 2, box, 0.5))
  detections.push(@moondeteval.Detection::new(106, 2, 1, box, 0.5))
  let report = @moondeteval.evaluate(dataset, detections)
  let counts = report.counts()
  assert_eq(counts.images(), 2)
  assert_eq(counts.categories(), 2)
  assert_eq(counts.ground_truths(), 1)
  assert_eq(counts.detections(), 107)
  assert_eq(counts.evaluated_detections(), 102)
  assert_eq(report.evaluator_version(), "0.1.0")
  assert_true(report.to_json_string().contains("\"evaluated_detections\":102"))
}

///|
test "out-of-image quality warnings preserve original-box metrics" {
  let outside = @moondeteval.Box::from_xywh(-5.0, 0.0, 20.0, 10.0)
  let inside = @moondeteval.Box::from_xywh(0.0, 0.0, 8.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 15, 10)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(7, 1, 1, outside, area=200.0)],
  )
  let exact = @moondeteval.evaluate(dataset, [
    @moondeteval.Detection::new(8, 1, 1, outside, 0.9),
  ])
  assert_eq(exact.summary().ap50(), 1.0)
  let warnings = exact.quality_warnings()
  assert_eq(warnings.length(), 2)
  assert_eq(warnings[0].source(), "ground_truth")
  assert_eq(warnings[0].record_id(), 7)
  assert_eq(warnings[0].kind(), "outside_image")
  assert_eq(warnings[1].source(), "detection")
  assert_eq(warnings[1].record_id(), 8)
  warnings.clear()
  assert_eq(exact.quality_warnings().length(), 2)
  let clipped = @moondeteval.evaluate(dataset, [
    @moondeteval.Detection::new(9, 1, 1, inside, 0.9),
  ])
  assert_true(clipped.summary().ap50() < exact.summary().ap50())
  assert_eq(clipped.quality_warnings().length(), 1)
}

///|
test "empty predictions have zero AP with an eligible ground truth" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [
      @moondeteval.Category::new(1, "present"),
      @moondeteval.Category::new(2, "empty"),
    ],
    [@moondeteval.GroundTruth::new(1, 1, 1, box, area=400.0)],
  )
  let report = @moondeteval.evaluate(dataset, [])
  assert_eq(report.summary().ap(), 0.0)
  assert_eq(report.classes()[1].metrics().ap(), -1.0)
  assert_eq(report.summary().ar100(), 0.0)
}

///|
test "higher scored false positive reduces AP and recall is limited by maxDets" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let far = @moondeteval.Box::from_xywh(50.0, 50.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 1, box, area=400.0)],
  )
  let wrong = @moondeteval.Detection::new(1, 1, 1, far, 0.9)
  let correct = @moondeteval.Detection::new(2, 1, 1, box, 0.8)
  let report = @moondeteval.evaluate(dataset, [wrong, correct])
  assert_true(report.summary().ap50() > 0.499999)
  assert_true(report.summary().ap50() < 0.500001)
  assert_eq(report.summary().ar1(), 0.0)
  assert_eq(report.summary().ar10(), 1.0)
}

///|
test "crowd match is ignored and duplicate prediction is false positive" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let crowd_box = @moondeteval.Box::from_xywh(40.0, 40.0, 40.0, 40.0)
  let inside_crowd = @moondeteval.Box::from_xywh(45.0, 45.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(1, "object")],
    [
      @moondeteval.GroundTruth::new(1, 1, 1, box, area=400.0),
      @moondeteval.GroundTruth::new(
        2,
        1,
        1,
        crowd_box,
        area=1600.0,
        iscrowd=true,
      ),
    ],
  )
  let crowd = @moondeteval.Detection::new(1, 1, 1, inside_crowd, 0.99)
  let correct = @moondeteval.Detection::new(2, 1, 1, box, 0.9)
  let duplicate = @moondeteval.Detection::new(3, 1, 1, box, 0.8)
  let report = @moondeteval.evaluate(dataset, [crowd, correct, duplicate])
  assert_true(report.summary().ap50() > 0.999999)
  assert_eq(report.summary().ar100(), 1.0)
}

///|
test "unknown and duplicate detection identifiers fail before scoring" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(1, "object")],
    [],
  )
  let known = @moondeteval.Detection::new(1, 1, 1, box, 0.5)
  try @moondeteval.evaluate(dataset, [known, known]) catch {
    @moondeteval.InvalidInput(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate accepted")
  }
  let unknown = @moondeteval.Detection::new(2, 2, 1, box, 0.5)
  try @moondeteval.evaluate(dataset, [unknown]) catch {
    @moondeteval.InvalidInput(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unknown image accepted")
  }
}

///|
test "diagnostics explain crowd, true positive, false positive, and false negative" {
  let regular = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let crowd_box = @moondeteval.Box::from_xywh(40.0, 40.0, 40.0, 40.0)
  let inside_crowd = @moondeteval.Box::from_xywh(45.0, 45.0, 10.0, 10.0)
  let missed = @moondeteval.Box::from_xywh(100.0, 100.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 200, 200)],
    [@moondeteval.Category::new(1, "object")],
    [
      @moondeteval.GroundTruth::new(1, 1, 1, regular, area=400.0),
      @moondeteval.GroundTruth::new(
        2,
        1,
        1,
        crowd_box,
        area=1600.0,
        iscrowd=true,
      ),
      @moondeteval.GroundTruth::new(3, 1, 1, missed, area=400.0),
    ],
  )
  let predictions = [
    @moondeteval.Detection::new(10, 1, 1, inside_crowd, 0.99),
    @moondeteval.Detection::new(11, 1, 1, regular, 0.9),
    @moondeteval.Detection::new(12, 1, 1, regular, 0.8),
  ]
  let plain = @moondeteval.evaluate(dataset, predictions)
  let traced = @moondeteval.evaluate_with_diagnostics(dataset, predictions)
  assert_eq(plain.summary().ap(), traced.summary().ap())
  assert_eq(plain.summary().ar100(), traced.summary().ar100())
  assert_eq(plain.diagnostics().length(), 0)
  let trace = traced.diagnostics()
  assert_eq(trace.length(), 40)
  assert_eq(trace[0].iou_threshold(), 0.5)
  assert_eq(trace[0].status(), "ignored")
  assert_eq(trace[0].reason(), "crowd")
  assert_eq(trace[0].detection_id(), Some(10))
  assert_eq(trace[0].ground_truth_id(), Some(2))
  assert_eq(trace[1].status(), "tp")
  assert_eq(trace[1].ground_truth_id(), Some(1))
  assert_eq(trace[2].status(), "fp")
  assert_eq(trace[3].status(), "fn")
  assert_eq(trace[3].ground_truth_id(), Some(3))
}

///|
test "custom IoU thresholds change AP while AP50 and AP75 stay fixed" {
  let truth_box = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 10.0)
  let prediction_box = @moondeteval.Box::from_xywh(0.0, 0.0, 17.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 1, truth_box, area=200.0)],
  )
  let predictions = [@moondeteval.Detection::new(1, 1, 1, prediction_box, 0.9)]
  let thresholds = [0.9]
  let config = @moondeteval.EvalConfig::new(
    thresholds,
    include_diagnostics=true,
  )
  thresholds[0] = 0.5
  let report = @moondeteval.evaluate_with_config(dataset, predictions, config)
  assert_eq(report.config().iou_thresholds(), [0.9])
  assert_eq(report.summary().ap(), 0.0)
  assert_eq(report.summary().ap50(), 1.0)
  assert_eq(report.summary().ap75(), 1.0)
  assert_eq(report.diagnostics().length(), 2)
  assert_eq(report.diagnostics()[0].status(), "fp")
  assert_eq(report.diagnostics()[1].status(), "fn")
}

///|
test "evaluation configuration rejects empty and non-increasing thresholds" {
  try @moondeteval.EvalConfig::new([]) catch {
    @moondeteval.InvalidConfig(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("empty thresholds accepted")
  }
  try @moondeteval.EvalConfig::new([0.5, 0.5]) catch {
    @moondeteval.InvalidConfig(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate thresholds accepted")
  }
  try @moondeteval.EvalConfig::new([1.1]) catch {
    @moondeteval.InvalidConfig(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("out-of-range threshold accepted")
  }
}

///|
test "explicit ground-truth area crosses both COCO bin boundaries" {
  let bbox = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let areas = [1023.999, 1024.0, 1024.001, 9215.999, 9216.0, 9216.001]
  let small = [true, true, false, false, false, false]
  let medium = [false, true, true, true, true, false]
  let large = [false, false, false, false, true, true]
  for index, area in areas {
    let dataset = @moondeteval.Dataset::new(
      [@moondeteval.Image::new(1, 100, 100)],
      [@moondeteval.Category::new(1, "object")],
      [@moondeteval.GroundTruth::new(1, 1, 1, bbox, area~)],
    )
    let report = @moondeteval.evaluate(dataset, [
      @moondeteval.Detection::new(1, 1, 1, bbox, 0.9),
    ])
    assert_eq(
      report.summary().ap_small(),
      if small[index] {
        1.0
      } else {
        -1.0
      },
    )
    assert_eq(
      report.summary().ap_medium(),
      if medium[index] {
        1.0
      } else {
        -1.0
      },
    )
    assert_eq(
      report.summary().ap_large(),
      if large[index] {
        1.0
      } else {
        -1.0
      },
    )
  }
}

///|
test "exact IoU threshold and one are inclusive while the next value is not" {
  let truth = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let half = @moondeteval.Box::from_xywh(0.0, 0.0, 5.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 1, truth, area=100.0)],
  )
  let config = @moondeteval.EvalConfig::new(
    [0.5, 0.5000000001, 1.0],
    include_diagnostics=true,
  )
  let report = @moondeteval.evaluate_with_config(
    dataset,
    [@moondeteval.Detection::new(1, 1, 1, half, 0.9)],
    config,
  )
  assert_eq(report.summary().ap50(), 1.0)
  assert_eq(report.diagnostics()[0].status(), "tp")
  assert_eq(report.diagnostics()[1].status(), "fp")
  assert_eq(report.diagnostics()[2].status(), "fn")
  let perfect = @moondeteval.evaluate_with_config(
    dataset,
    [@moondeteval.Detection::new(2, 1, 1, truth, 0.9)],
    @moondeteval.EvalConfig::new([1.0]),
  )
  assert_eq(perfect.summary().ap(), 1.0)
}

///|
test "maxDets tie at rank one hundred preserves input order per category" {
  let truth = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let far = @moondeteval.Box::from_xywh(30.0, 30.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 50, 50)],
    [@moondeteval.Category::new(1, "target")],
    [@moondeteval.GroundTruth::new(1, 1, 1, truth, area=100.0)],
  )
  let predictions : Array[@moondeteval.Detection] = []
  for index in 0..<100 {
    predictions.push(@moondeteval.Detection::new(index, 1, 1, far, 0.5))
  }
  predictions.push(@moondeteval.Detection::new(100, 1, 1, truth, 0.5))
  let missed = @moondeteval.evaluate_with_config(
    dataset,
    predictions,
    @moondeteval.EvalConfig::new([0.5], include_image_summaries=true),
  )
  assert_eq(missed.summary().ap(), 0.0)
  assert_eq(missed.image_summaries()[0].fp(), 100)
  assert_eq(missed.image_summaries()[0].fn_count(), 1)
  predictions[99] = predictions[100]
  predictions.pop() |> ignore
  let retained = @moondeteval.evaluate_with_config(
    dataset,
    predictions,
    @moondeteval.EvalConfig::new([0.5]),
  )
  assert_true(retained.summary().ap() > 0.009999)
  assert_true(retained.summary().ap() < 0.010001)
}

///|
test "image summaries use fixed IoU 0.50 and retain metric invariance" {
  let truth = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let shifted = @moondeteval.Box::from_xywh(2.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 30, 30)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 1, truth, area=100.0)],
  )
  let predictions = [@moondeteval.Detection::new(1, 1, 1, shifted, 0.9)]
  let plain = @moondeteval.evaluate_with_config(
    dataset,
    predictions,
    @moondeteval.EvalConfig::new([0.75]),
  )
  let ranked = @moondeteval.evaluate_with_config(
    dataset,
    predictions,
    @moondeteval.EvalConfig::new([0.75], include_image_summaries=true),
  )
  assert_eq(plain.summary().ap(), ranked.summary().ap())
  assert_eq(plain.summary().ap50(), ranked.summary().ap50())
  assert_eq(ranked.summary().ap(), 0.0)
  assert_eq(ranked.summary().ap50(), 1.0)
  assert_eq(ranked.image_summaries()[0].tp(), 1)
  assert_eq(ranked.image_summaries()[0].fp(), 0)
  assert_eq(ranked.image_summaries()[0].fn_count(), 0)
}

///|
test "image summaries exclude crowd matches and predictions after maxDets" {
  let truth = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let crowd = @moondeteval.Box::from_xywh(20.0, 20.0, 20.0, 20.0)
  let far = @moondeteval.Box::from_xywh(50.0, 50.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(1, "object")],
    [
      @moondeteval.GroundTruth::new(1, 1, 1, truth, area=100.0),
      @moondeteval.GroundTruth::new(2, 1, 1, crowd, area=400.0, iscrowd=true),
    ],
  )
  let predictions : Array[@moondeteval.Detection] = [
    @moondeteval.Detection::new(1, 1, 1, crowd, 1.0),
  ]
  for index in 0..<99 {
    predictions.push(@moondeteval.Detection::new(index + 2, 1, 1, far, 0.9))
  }
  predictions.push(@moondeteval.Detection::new(101, 1, 1, truth, 0.1))
  let report = @moondeteval.evaluate_with_config(
    dataset,
    predictions,
    @moondeteval.EvalConfig::new([0.5], include_image_summaries=true),
  )
  let image = report.image_summaries()[0]
  assert_eq(image.tp(), 0)
  assert_eq(image.fp(), 99)
  assert_eq(image.fn_count(), 1)
  assert_eq(image.ignored(), 1)
  assert_eq(report.counts().evaluated_detections(), 100)
}

///|
test "exported PR samples are the AP envelope and ignore crowd" {
  let first = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let second = @moondeteval.Box::from_xywh(20.0, 0.0, 10.0, 10.0)
  let crowd = @moondeteval.Box::from_xywh(40.0, 0.0, 10.0, 10.0)
  let far = @moondeteval.Box::from_xywh(60.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [
      @moondeteval.Category::new(1, "present"),
      @moondeteval.Category::new(2, "absent"),
    ],
    [
      @moondeteval.GroundTruth::new(1, 1, 1, first, area=100.0),
      @moondeteval.GroundTruth::new(2, 1, 1, second, area=100.0),
      @moondeteval.GroundTruth::new(3, 1, 1, crowd, area=100.0, iscrowd=true),
    ],
  )
  let predictions = [
    @moondeteval.Detection::new(1, 1, 1, far, 0.9),
    @moondeteval.Detection::new(2, 1, 1, first, 0.8),
    @moondeteval.Detection::new(3, 1, 1, crowd, 0.7),
    @moondeteval.Detection::new(4, 1, 1, second, 0.6),
  ]
  let plain = @moondeteval.evaluate(dataset, predictions)
  let config = @moondeteval.EvalConfig::new([0.5, 0.75], include_pr_curves=true)
  let report = @moondeteval.evaluate_with_config(dataset, predictions, config)
  assert_eq(plain.summary().ap50(), report.summary().ap50())
  let grid = report.recall_thresholds()
  assert_eq(grid.length(), 101)
  assert_eq(grid[0], 0.0)
  assert_eq(grid[50], 0.5)
  assert_eq(grid[100], 1.0)
  let curves = report.pr_curves()
  assert_eq(curves.length(), 4)
  assert_eq(curves[0].category_id(), 1)
  assert_eq(curves[0].iou_threshold(), 0.5)
  assert_eq(curves[0].max_recall(), 1.0)
  assert_eq(curves[0].precision().length(), 101)
  for value in curves[0].precision() {
    assert_true(value > 0.6666666 && value < 0.6666667)
  }
  assert_true(curves[0].ap() > 0.6666666 && curves[0].ap() < 0.6666667)
  let changed = curves[0].precision()
  changed[0] = 0.0
  assert_true(report.pr_curves()[0].precision()[0] > 0.6666666)
  assert_eq(curves[1].iou_threshold(), 0.75)
  assert_eq(curves[2].category_id(), 2)
  assert_eq(curves[2].ap(), -1.0)
  assert_eq(curves[2].max_recall(), -1.0)
  assert_eq(curves[2].precision().length(), 101)
  assert_eq(curves[2].precision()[50], -1.0)
}

///|
test "PR export keeps empty-prediction precision zero and custom threshold scope" {
  let truth = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20)],
    [@moondeteval.Category::new(1, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 1, truth, area=100.0)],
  )
  let report = @moondeteval.evaluate_with_config(
    dataset,
    [],
    @moondeteval.EvalConfig::new([0.75], include_pr_curves=true),
  )
  assert_eq(report.pr_curves().length(), 1)
  assert_eq(report.pr_curves()[0].iou_threshold(), 0.75)
  assert_eq(report.pr_curves()[0].precision(), Array::make(101, 0.0))
  assert_eq(report.pr_curves()[0].max_recall(), 0.0)
  assert_eq(report.pr_curves()[0].ap(), 0.0)
  let shifted = @moondeteval.Box::from_xywh(2.0, 0.0, 10.0, 10.0)
  let partial = @moondeteval.evaluate_with_config(
    dataset,
    [@moondeteval.Detection::new(2, 1, 1, shifted, 0.9)],
    @moondeteval.EvalConfig::new([0.75], include_pr_curves=true),
  )
  assert_eq(partial.summary().ap50(), 1.0)
  assert_eq(partial.pr_curves()[0].ap(), 0.0)
  assert_eq(@moondeteval.evaluate(dataset, []).pr_curves().length(), 0)
}

///|
test "false-positive labels follow duplicate, wrong-class, localization, background priority" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 20.0, 20.0)
  let shifted = @moondeteval.Box::from_xywh(10.0, 0.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [
      @moondeteval.Image::new(1, 100, 100),
      @moondeteval.Image::new(2, 100, 100),
      @moondeteval.Image::new(3, 100, 100),
      @moondeteval.Image::new(4, 100, 100),
    ],
    [
      @moondeteval.Category::new(1, "predicted"),
      @moondeteval.Category::new(2, "other"),
    ],
    [
      @moondeteval.GroundTruth::new(1, 1, 1, box, area=400.0),
      @moondeteval.GroundTruth::new(2, 2, 2, box, area=400.0),
      @moondeteval.GroundTruth::new(3, 3, 1, box, area=400.0),
    ],
  )
  let predictions = [
    @moondeteval.Detection::new(10, 1, 1, box, 0.9),
    @moondeteval.Detection::new(11, 1, 1, box, 0.8),
    @moondeteval.Detection::new(12, 2, 1, box, 0.7),
    @moondeteval.Detection::new(13, 3, 1, shifted, 0.6),
    @moondeteval.Detection::new(14, 4, 1, shifted, 0.5),
  ]
  let trace = @moondeteval.evaluate_with_diagnostics(dataset, predictions).diagnostics()
  assert_eq(trace[1].status(), "fp")
  assert_eq(trace[1].reason(), "duplicate")
  assert_eq(trace[2].reason(), "wrong_class")
  assert_eq(trace[3].reason(), "localization")
  assert_eq(trace[5].reason(), "background")
}

///|
test "COCO bbox ignores only crowd while explicit mode honors source ignore" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20)],
    [@moondeteval.Category::new(1, "box")],
    [@moondeteval.GroundTruth::new(1, 1, 1, box, area=100.0, ignore=true)],
  )
  let prediction = @moondeteval.Detection::new(1, 1, 1, box, 0.9)
  let compatible = @moondeteval.evaluate_with_diagnostics(dataset, [prediction])
  assert_eq(compatible.config().ignore_policy(), "coco_bbox")
  assert_eq(compatible.summary().ap50(), 1.0)
  assert_eq(compatible.diagnostics()[0].status(), "tp")
  let explicit = @moondeteval.EvalConfig::new(
    [0.5],
    include_diagnostics=true,
    ignore_policy="respect_explicit",
  )
  let respected = @moondeteval.evaluate_with_config(
    dataset,
    [prediction],
    explicit,
  )
  assert_eq(respected.summary().ap50(), -1.0)
  assert_eq(respected.diagnostics()[0].status(), "ignored")
  assert_eq(respected.diagnostics()[0].reason(), "ground_truth_ignore")
  try @moondeteval.EvalConfig::new([0.5], ignore_policy="unknown") catch {
    @moondeteval.InvalidConfig(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("unknown policy accepted")
  }
}

///|
test "equal scores across images accumulate in sorted image order" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let far = @moondeteval.Box::from_xywh(50.0, 50.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(2, 100, 100), @moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(1, "box")],
    [
      @moondeteval.GroundTruth::new(1, 1, 1, box, area=100.0),
      @moondeteval.GroundTruth::new(2, 2, 1, box, area=100.0),
    ],
  )
  let predictions = [
    @moondeteval.Detection::new(10, 2, 1, box, 0.9),
    @moondeteval.Detection::new(11, 1, 1, far, 0.9),
    @moondeteval.Detection::new(12, 1, 1, box, 0.8),
  ]
  let ap = @moondeteval.evaluate(dataset, predictions).summary().ap()
  assert_true(ap > 0.666666 && ap < 0.666667)
}

///|
test "COCO recall grid rounds 70 percent like the reference implementation" {
  let truths : Array[@moondeteval.GroundTruth] = []
  let predictions : Array[@moondeteval.Detection] = []
  for index in 0..<10 {
    let box = @moondeteval.Box::from_xywh(
      index.to_double() * 20.0,
      0.0,
      10.0,
      10.0,
    )
    truths.push(
      @moondeteval.GroundTruth::new(
        (index + 1).to_int64(),
        1,
        1,
        box,
        area=100.0,
      ),
    )
    if index < 7 {
      predictions.push(@moondeteval.Detection::new(index + 1, 1, 1, box, 0.9))
    }
  }
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 200, 20)],
    [@moondeteval.Category::new(1, "box")],
    truths,
  )
  let config = @moondeteval.EvalConfig::new([0.5], include_pr_curves=true)
  let report = @moondeteval.evaluate_with_config(dataset, predictions, config)
  assert_true(report.recall_thresholds()[70] > 0.7)
  let curve = report.pr_curves()[0]
  assert_eq(curve.precision()[69], 1.0)
  assert_eq(curve.precision()[70], 0.0)
  assert_true(curve.ap() > 0.693069 && curve.ap() < 0.693070)
}
