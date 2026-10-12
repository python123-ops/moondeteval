///|
test "independent module calls MoonDetEval public API" {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 10, 10)],
    [@moondeteval.Category::new(2, "object")],
    [@moondeteval.GroundTruth::new(3, 1, 2, box, area=100.0)],
  )
  let detection = @moondeteval.Detection::new(4, 1, 2, box, 0.9)
  let report = @moondeteval.evaluate(dataset, [detection])
  assert_eq(report.summary().ap50(), 1.0)
  assert_eq(report.counts().evaluated_detections(), 1)
  assert_eq(report.quality_warnings().length(), 0)
  let comparison = @moondeteval.compare_predictions(dataset, [detection], [])
  assert_eq(comparison.metrics()[1].name(), "ap50")
  assert_eq(comparison.metrics()[1].delta(), Some(-1.0))
  let yolo = @moondeteval.parse_yolo_detections(
    "0 0.5 0.5 1 1 0.9",
    dataset,
    1,
    [2],
    first_detection_id=5,
  )
  assert_eq(yolo[0].id(), 5)
  assert_eq(@moondeteval.evaluate(dataset, yolo).summary().ap50(), 1.0)
  let manifest = @moondeteval.parse_yolo_manifest(
    "{\"category_ids\":[2],\"images\":[{\"image_id\":1,\"file\":\"labels/1.txt\"}]}",
    dataset,
  )
  assert_eq(manifest.category_ids()[0], 2)
  assert_eq(manifest.images()[0].image_id(), 1)
  assert_eq(manifest.images()[0].file(), "labels/1.txt")
}

///|
test "MBMOT detector frame adapts without tracking-state coupling" {
  let mbbox = @mbmot.BoundingBox::from_xywh(0.0, 0.0, 10.0, 10.0)
  let mbdetection = @mbmot.Detection::new(mbbox, 0.9, 2)
  let predictions = @consumer.adapt_mbmot_frame(1, 40, [mbdetection])
  assert_eq(predictions[0].id(), 40)
  assert_eq(predictions[0].image_id(), 1)
  assert_eq(predictions[0].category_id(), 2)
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 10, 10)],
    [@moondeteval.Category::new(2, "object")],
    [@moondeteval.GroundTruth::new(3, 1, 2, box, area=100.0)],
  )
  assert_eq(@moondeteval.evaluate(dataset, predictions).summary().ap50(), 1.0)
}

///|
test "two MBMOT frames preserve image and category mapping with unique IDs" {
  let box1 = @mbmot.BoundingBox::from_xywh(0.0, 0.0, 10.0, 10.0)
  let box2 = @mbmot.BoundingBox::from_xywh(20.0, 5.0, 8.0, 8.0)
  let first = @mbmot.Detection::new(box1, 0.9, 5)
  let second = @mbmot.Detection::new(box2, 0.8, 6)
  let predictions = @consumer.adapt_mbmot_frames(
    [(11, [first]), (29, [second])],
    [(5, 7), (6, 8)],
    40,
  )
  assert_eq(predictions.length(), 2)
  assert_eq(
    (
      predictions[0].id(),
      predictions[0].image_id(),
      predictions[0].category_id(),
    ),
    (40, 11, 7),
  )
  assert_eq(
    (
      predictions[1].id(),
      predictions[1].image_id(),
      predictions[1].category_id(),
    ),
    (41, 29, 8),
  )
  let truth1 = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let truth2 = @moondeteval.Box::from_xywh(20.0, 5.0, 8.0, 8.0)
  let dataset = @moondeteval.Dataset::new(
    [
      @moondeteval.Image::new(11, 100, 100),
      @moondeteval.Image::new(29, 100, 100),
    ],
    [
      @moondeteval.Category::new(7, "person"),
      @moondeteval.Category::new(8, "bike"),
    ],
    [
      @moondeteval.GroundTruth::new(101, 11, 7, truth1, area=100.0),
      @moondeteval.GroundTruth::new(102, 29, 8, truth2, area=64.0),
    ],
  )
  let direct = [
    @moondeteval.Detection::new(40, 11, 7, truth1, 0.9),
    @moondeteval.Detection::new(41, 29, 8, truth2, 0.8),
  ]
  let config = @moondeteval.EvalConfig::new(
    @moondeteval.EvalConfig::coco().iou_thresholds(),
    include_image_summaries=true,
  )
  let adapted = @moondeteval.evaluate_with_config(dataset, predictions, config)
  let reference = @moondeteval.evaluate_with_config(dataset, direct, config)
  assert_eq(adapted.summary().ap50(), 1.0)
  assert_eq(adapted.summary().to_json(), reference.summary().to_json())
  assert_eq(Json(adapted.image_summaries()), Json(reference.image_summaries()))
  assert_eq(adapted.image_summaries().length(), 2)
}

///|
test "MBMOT bridge rejects mapping ambiguity, repeated frames, and ID overflow" {
  let box = @mbmot.BoundingBox::from_xywh(0.0, 0.0, 10.0, 10.0)
  let detection = @mbmot.Detection::new(box, 0.9, 5)
  try
    @consumer.adapt_mbmot_frames([(1, [detection])], [(5, 7), (5, 8)], 0)
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("duplicate MBMOT class"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("ambiguous mapping accepted")
  }
  try @consumer.adapt_mbmot_frames([(1, [detection])], [(6, 7)], 0) catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("unmapped MBMOT class"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("unmapped class accepted")
  }
  try
    @consumer.adapt_mbmot_frames([(1, [detection]), (1, [])], [(5, 7)], 0)
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("duplicate MBMOT frame"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("repeated frame accepted")
  }
  try
    @consumer.adapt_mbmot_frames(
      [(1, [detection, detection])],
      [(5, 7)],
      2147483647,
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("ID exceeds"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("overflowing ID accepted")
  }
  try @consumer.adapt_mbmot_frame(1, 2147483647, [detection, detection]) catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("ID exceeds"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("single-frame overflowing ID accepted")
  }
}
