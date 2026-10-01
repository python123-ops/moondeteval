///|
test "YOLO TXT maps classes and normalized boxes into evaluated detections" {
  let first = @moondeteval.Box::from_xywh(0.0, 60.0, 160.0, 80.0)
  let second = @moondeteval.Box::from_xywh(200.0, 0.0, 80.0, 100.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(9, 320, 200)],
    [@moondeteval.Category::new(7, "a"), @moondeteval.Category::new(42, "b")],
    [
      @moondeteval.GroundTruth::new(1, 9, 7, first, area=12800.0),
      @moondeteval.GroundTruth::new(2, 9, 42, second, area=8000.0),
    ],
  )
  let source = " 1\t0.25 0.5 0.5 0.4 0.9\r\n\n0 0.75 0.25 0.25 0.5 0.8\n"
  let detections = @moondeteval.parse_yolo_detections(
    source,
    dataset,
    9,
    [42, 7],
    first_detection_id=10,
  )
  assert_eq(detections.length(), 2)
  assert_eq(detections[0].id(), 10)
  assert_eq(detections[1].id(), 11)
  assert_eq(detections[0].category_id(), 7)
  assert_eq(detections[1].category_id(), 42)
  assert_true(detections[0].bbox().iou(first) > 0.999999)
  assert_true(detections[1].bbox().iou(second) > 0.999999)
  let report = @moondeteval.evaluate(dataset, detections)
  assert_eq(report.summary().ap50(), 1.0)
  assert_eq(report.quality_warnings().length(), 0)
}

///|
test "YOLO normalized input may produce a warned out-of-image box" {
  let box = @moondeteval.Box::from_xywh(-25.0, 0.0, 50.0, 50.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(3, "object")],
    [@moondeteval.GroundTruth::new(1, 1, 3, box, area=2500.0)],
  )
  let detections = @moondeteval.parse_yolo_detections(
    "0 0 0.25 0.5 0.5 0.9",
    dataset,
    1,
    [3],
  )
  let report = @moondeteval.evaluate(dataset, detections)
  assert_eq(report.summary().ap50(), 1.0)
  assert_eq(report.quality_warnings().length(), 2)
  assert_eq(report.quality_warnings()[1].record_id(), 0)
}

///|
test "YOLO TXT errors include line and field" {
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(3, "object")],
    [],
  )
  assert_eq(
    @moondeteval.parse_yolo_detections("\n\t\n", dataset, 1, [3]).length(),
    0,
  )
  try
    @moondeteval.parse_yolo_detections(
      "0 0.5 0.5 0.2 0.2 0.9\n1 0.5 0.5 0.2 0.2 0.8",
      dataset,
      1,
      [3],
    )
  catch {
    @moondeteval.InvalidInput(message) => {
      assert_true(message.contains("line 2"))
      assert_true(message.contains("class_index"))
    }
    _ => fail("wrong error")
  } noraise {
    _ => fail("unmapped class accepted")
  }
  try
    @moondeteval.parse_yolo_detections("0 0.5 0.5 0 0.2 0.9", dataset, 1, [3])
  catch {
    @moondeteval.InvalidInput(message) => assert_true(message.contains("width"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("zero width accepted")
  }
  try
    @moondeteval.parse_yolo_detections("0 0.5 0.5 0.2 0.2 nan", dataset, 1, [3])
  catch {
    @moondeteval.InvalidInput(message) => assert_true(message.contains("score"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("nan accepted")
  }
  try
    @moondeteval.parse_yolo_detections("0 1.1 0.5 0.2 0.2 0.9", dataset, 1, [3])
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("center_x"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("out-of-range center accepted")
  }
  try @moondeteval.parse_yolo_detections("0 0.5 0.5", dataset, 1, [3]) catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("six columns"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("short row accepted")
  }
  for unsupported in ["0 0.5 0.5 0.2 0.2", "0 0.5 0.5 0.2 0.2 0.9 8"] {
    try @moondeteval.parse_yolo_detections(unsupported, dataset, 1, [3]) catch {
      @moondeteval.InvalidInput(message) =>
        assert_true(message.contains("six columns"))
      _ => fail("wrong error")
    } noraise {
      _ => fail("unsupported YOLO row accepted")
    }
  }
}

///|
test "YOLO TXT validates image/category mapping and generated ID range" {
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(3, "object")],
    [],
  )
  try @moondeteval.parse_yolo_detections("", dataset, 2, [3]) catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("image_id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("unknown image accepted")
  }
  try @moondeteval.parse_yolo_detections("", dataset, 1, [4]) catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("category_ids[0]"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("unknown category accepted")
  }
  try
    @moondeteval.parse_yolo_detections(
      "0 0.5 0.5 0.2 0.2 0.9\n0 0.5 0.5 0.2 0.2 0.8",
      dataset,
      1,
      [3],
      first_detection_id=2147483647,
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("ID exceeds"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("overflowing ID accepted")
  }
}
