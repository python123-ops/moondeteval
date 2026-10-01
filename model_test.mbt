///|
test "dataset accepts sparse and zero-valued external IDs" {
  let image = @moondeteval.Image::new(0, 640, 480)
  let category = @moondeteval.Category::new(42, "person")
  let bbox = @moondeteval.Box::from_xywh(10.0, 20.0, 30.0, 40.0)
  let truth = @moondeteval.GroundTruth::new(0, 0, 42, bbox, area=1200.0)
  let dataset = @moondeteval.Dataset::new([image], [category], [truth])
  assert_eq(dataset.images()[0].id(), 0)
  assert_eq(dataset.categories()[0].name(), "person")
  assert_eq(dataset.truths()[0].bbox().to_xywh(), (10.0, 20.0, 30.0, 40.0))
}

///|
test "dataset rejects duplicate IDs and unknown references" {
  let image = @moondeteval.Image::new(7, 20, 20)
  let category = @moondeteval.Category::new(3, "box")
  let bbox = @moondeteval.Box::new(0.0, 0.0, 4.0, 4.0)
  try @moondeteval.Dataset::new([image, image], [category], []) catch {
    @moondeteval.InvalidInput(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("duplicate image was accepted")
  }
  let truth = @moondeteval.GroundTruth::new(1, 8, 3, bbox, area=16.0)
  try @moondeteval.Dataset::new([image], [category], [truth]) catch {
    @moondeteval.InvalidInput(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("unknown image was accepted")
  }
}

///|
test "detector scores only need to be finite" {
  let bbox = @moondeteval.Box::new(0.0, 0.0, 4.0, 4.0)
  let high_score = @moondeteval.Detection::new(1, 0, 42, bbox, 1.5)
  assert_eq(high_score.score(), 1.5)
  try @moondeteval.Detection::new(2, 0, 42, bbox, @double.not_a_number) catch {
    @moondeteval.InvalidInput(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("NaN score was accepted")
  }
}
