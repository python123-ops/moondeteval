///|
test "COCO xywh conversion and ordinary IoU" {
  let first = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0)
  let shifted = @moondeteval.Box::from_xywh(5.0, 0.0, 10.0, 10.0)
  assert_eq(first.to_xywh(), (0.0, 0.0, 10.0, 10.0))
  assert_eq(first.iou(first), 1.0)
  assert_eq(first.iou(shifted), 1.0 / 3.0)
  assert_eq(shifted.iou(first), first.iou(shifted))
}

///|
test "touching edges do not overlap" {
  let left = @moondeteval.Box::new(0.0, 0.0, 2.0, 2.0)
  let right = @moondeteval.Box::new(2.0, 0.0, 4.0, 2.0)
  assert_eq(left.iou(right), 0.0)
}

///|
test "IoU remains finite when the direct area sum would overflow" {
  let large = @moondeteval.Box::new(0.0, 0.0, 1.0e154, 1.0e154)
  assert_eq(large.iou(large), 1.0)
}

///|
test "invalid and non-finite boxes are rejected" {
  try @moondeteval.Box::new(0.0, 0.0, 0.0, 1.0) catch {
    @moondeteval.InvalidBox(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("zero-width box was accepted")
  }
  try @moondeteval.Box::new(0.0, 0.0, @double.infinity, 1.0) catch {
    @moondeteval.InvalidBox(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("infinite coordinate was accepted")
  }
}
