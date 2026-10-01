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
