///|
test "COCO JSON parses into the in-memory evaluator" {
  let dataset = @moondeteval.parse_coco_dataset(
    "{\"images\":[{\"id\":1,\"width\":100,\"height\":100}],\"categories\":[{\"id\":4,\"name\":\"object\"}],\"annotations\":[{\"id\":9,\"image_id\":1,\"category_id\":4,\"bbox\":[0,0,20,20],\"area\":400}]}",
  )
  let predictions = @moondeteval.parse_coco_detections(
    "[{\"image_id\":1,\"category_id\":4,\"bbox\":[0,0,20,20],\"score\":0.9}]",
  )
  assert_eq(predictions[0].id(), 0)
  assert_true(
    @moondeteval.evaluate(dataset, predictions).summary().ap() > 0.999999,
  )
}

///|
test "COCO JSON accepts empty predictions and locates malformed boxes" {
  let predictions = @moondeteval.parse_coco_detections("[]")
  assert_eq(predictions.length(), 0)
  try
    @moondeteval.parse_coco_detections(
      "[{\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,1],\"score\":0.5}]",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("detections[0].bbox"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("short bbox accepted")
  }
}

///|
test "COCO JSON reports the record index for invalid field types" {
  try
    @moondeteval.parse_coco_detections(
      "[{\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,1,1],\"score\":0.5},{\"image_id\":\"bad\",\"category_id\":1,\"bbox\":[0,0,1,1],\"score\":0.5}]",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("detections[1]"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("invalid image id accepted")
  }
}
