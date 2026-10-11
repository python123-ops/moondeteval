///|
test "COCO uncompressed RLE area, IoU, and crowd denominator" {
  let first = @moondeteval.CocoRle::new(3, 4, [1, 2, 2, 3, 4])
  let second = @moondeteval.CocoRle::new(3, 4, [0, 3, 2, 1, 6])
  assert_eq(first.height(), 3)
  assert_eq(first.width(), 4)
  assert_eq(first.area(), 5)
  assert_eq(second.area(), 4)
  assert_eq(first.iou(second), 0.5)
  assert_eq(second.iou(first), 0.5)
  assert_eq(first.crowd_iou(second), 0.6)
  assert_eq(second.crowd_iou(first), 0.75)
}

///|
test "COCO RLE supports empty, full, touching, and zero-length runs" {
  let empty = @moondeteval.CocoRle::new(2, 3, [6])
  let full = @moondeteval.CocoRle::new(2, 3, [0, 6])
  let first_half = @moondeteval.CocoRle::new(2, 3, [0, 3, 3])
  let second_half = @moondeteval.CocoRle::new(2, 3, [3, 3])
  let equivalent = @moondeteval.CocoRle::new(2, 3, [0, 0, 0, 3, 3])
  assert_eq(empty.area(), 0)
  assert_eq(full.area(), 6)
  assert_eq(empty.iou(empty), 0.0)
  assert_eq(empty.iou(full), 0.0)
  assert_eq(full.iou(full), 1.0)
  assert_eq(first_half.iou(second_half), 0.0)
  assert_eq(first_half.iou(equivalent), 1.0)
  assert_eq(empty.crowd_iou(full), 0.0)
  assert_eq(first_half.crowd_iou(full), 1.0)
}

///|
test "COCO RLE copies input and rejects invalid coverage" {
  let counts = [1, 2, 3]
  let mask = @moondeteval.CocoRle::new(2, 3, counts)
  counts[1] = 0
  assert_eq(mask.area(), 2)
  for bad in [[1, 2], [1, -1, 6], [1, 2, 4], []] {
    try @moondeteval.CocoRle::new(2, 3, bad) catch {
      @moondeteval.InvalidInput(_) => ()
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("invalid RLE was accepted")
    }
  }
  for (height, width) in [(0, 3), (2, 0), (46341, 46341)] {
    try @moondeteval.CocoRle::new(height, width, [1]) catch {
      @moondeteval.InvalidInput(_) => ()
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("invalid dimensions were accepted")
    }
  }
  let other_shape = @moondeteval.CocoRle::new(3, 2, [1, 2, 3])
  try mask.iou(other_shape) catch {
    @moondeteval.InvalidInput(_) => ()
    _ => fail("unexpected error type")
  } noraise {
    _ => fail("different image dimensions were accepted")
  }
}
