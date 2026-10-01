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
