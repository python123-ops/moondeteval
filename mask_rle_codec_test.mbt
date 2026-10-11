///|
test "compressed COCO RLE fixtures preserve run differences" {
  for
    (height, width, runs, encoded) in [
      (3, 4, [1, 2, 2, 3, 4], "12212"),
      (3, 4, [0, 3, 2, 1, 6], "032N4"),
      (1, 220, [0, 100, 0, 1, 0, 119], "0T30mL0f3"),
      (1, 45, [0, 44, 1], "0\\11"),
      (1, 2147483647, [2147483647], "oooooo1"),
      (1, 2147483647, [0, 2147483647], "0oooooo1"),
      (
        1,
        2147483647,
        [0, 1000000000, 0, 1, 0, 1147483646],
        "0P`beim00Q`]ZVRO0m_]ZVR1",
      ),
    ] {
    let original = @moondeteval.CocoRle::new(height, width, runs)
    let decoded = @moondeteval.CocoRle::from_compressed(height, width, encoded)
    assert_eq(original.to_compressed(), encoded)
    assert_eq(decoded.to_compressed(), encoded)
    assert_eq(decoded.area(), original.area())
    assert_eq(
      decoded.iou(original),
      if original.area() == 0 {
        0.0
      } else {
        1.0
      },
    )
  }
}

///|
test "compressed COCO RLE rejects bad characters, truncation, and overflow" {
  for
    (encoded, expected) in [
      ("/", "character at 0"),
      ("p", "character at 0"),
      ("é", "character at 0"),
      ("\u0000", "character at 0"),
      ("P", "truncated at character 1"),
      ("PPPPPPP0", "run too long at character 0"),
      ("PPPPPP2", "invalid run at character 0"),
      ("O", "invalid run at character 0"),
      ("010M", "invalid run at character 3"),
      ("7", "invalid run at character 0"),
      ("1", "do not cover"),
      ("", "must not be empty"),
    ] {
    try @moondeteval.CocoRle::from_compressed(2, 3, encoded) catch {
      @moondeteval.InvalidInput(message) =>
        assert_true(message.contains(expected))
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("malformed compressed RLE accepted")
    }
  }
}

///|
test "segmentation JSON supports array, compressed counts, and escaped ASCII" {
  let array = @moondeteval.parse_coco_rle(
    "{\"size\":[3,4],\"counts\":[1,2,2,3,4]}",
  )
  let compressed = @moondeteval.parse_coco_rle(
    "{\"size\":[3,4],\"counts\":\"12212\"}",
  )
  let other = @moondeteval.parse_coco_rle(
    "{\"size\":[3,4],\"counts\":\"032N4\"}",
  )
  assert_eq(array.iou(compressed), 1.0)
  assert_eq(array.iou(other), 0.5)
  assert_eq(compressed.crowd_iou(other), 0.6)
  let escaped = @moondeteval.parse_coco_rle(
    "{\"size\":[1,45],\"counts\":\"0\\\\11\"}",
  )
  assert_eq(escaped.area(), 44)
  assert_eq(escaped.to_compressed(), "0\\11")
  let integral_numbers = @moondeteval.parse_coco_rle(
    "{\"size\":[1e0,6.0],\"counts\":[6e0]}",
  )
  assert_eq(integral_numbers.area(), 0)
}

///|
test "segmentation JSON errors locate invalid size and counts fields" {
  for
    (source, expected) in [
      ("{", "not valid JSON"),
      ("[[0,0,1,0,1,1]]", "must be an object"),
      ("{}", "size"),
      ("{\"size\":[2,3,4],\"counts\":[6]}", "size"),
      ("{\"size\":[2.5,3],\"counts\":[6]}", "size[0]"),
      ("{\"size\":[2,\"3\"],\"counts\":[6]}", "size[1]"),
      ("{\"size\":[0,3],\"counts\":[6]}", "positive"),
      ("{\"size\":[46341,46341],\"counts\":\"6\"}", "pixel count"),
      ("{\"size\":[2,3]}", "counts"),
      ("{\"size\":[2,3],\"counts\":true}", "counts"),
      ("{\"size\":[2,3],\"counts\":[1,-1,6]}", "counts[1]"),
      ("{\"size\":[2,3],\"counts\":[1,2.5,3]}", "counts[1]"),
      ("{\"size\":[2,3],\"counts\":[2147483648]}", "counts[0]"),
      ("{\"size\":[2,3],\"counts\":[1e400]}", "counts[0]"),
      ("{\"size\":[2,3],\"counts\":[true]}", "counts[0]"),
      ("{\"size\":[2,3],\"counts\":\"6P\"}", "character 2"),
    ] {
    try @moondeteval.parse_coco_rle(source) catch {
      @moondeteval.InvalidInput(message) =>
        assert_true(message.contains(expected))
      _ => fail("unexpected error type")
    } noraise {
      _ => fail("invalid segmentation JSON accepted")
    }
  }
}
