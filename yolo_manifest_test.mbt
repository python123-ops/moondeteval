///|
test "YOLO manifest preserves file order and class mapping" {
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(9, 320, 200), @moondeteval.Image::new(12, 80, 80)],
    [@moondeteval.Category::new(42, "a"), @moondeteval.Category::new(7, "b")],
    [],
  )
  let manifest = @moondeteval.parse_yolo_manifest(
    "{\"category_ids\":[42,7],\"images\":[{\"image_id\":12,\"file\":\"labels/12.txt\"},{\"image_id\":9,\"file\":\"labels/9.txt\"}]}",
    dataset,
  )
  assert_eq(manifest.category_ids(), [42, 7])
  assert_eq(manifest.images()[0].image_id(), 12)
  assert_eq(manifest.images()[1].file(), "labels/9.txt")
  let mapping = manifest.category_ids()
  mapping[0] = 7
  assert_eq(manifest.category_ids()[0], 42)
}

///|
test "YOLO manifest rejects unknown, duplicate and unsafe references" {
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(9, 320, 200), @moondeteval.Image::new(12, 80, 80)],
    [@moondeteval.Category::new(42, "a")],
    [],
  )
  for
    (source, expected) in [
      ("{\"category_ids\":[7],\"images\":[]}", "category_ids[0]"),
      (
        "{\"category_ids\":[42],\"images\":[{\"image_id\":13,\"file\":\"a.txt\"}]}",
        "images[0].image_id",
      ),
      (
        "{\"category_ids\":[42],\"images\":[{\"image_id\":9,\"file\":\"a.txt\"},{\"image_id\":9,\"file\":\"b.txt\"}]}",
        "duplicated",
      ),
      (
        "{\"category_ids\":[42],\"images\":[{\"image_id\":9,\"file\":\"a.txt\"},{\"image_id\":12,\"file\":\"a.txt\"}]}",
        "duplicated",
      ),
      (
        "{\"category_ids\":[42],\"images\":[{\"image_id\":9,\"file\":\"../a.txt\"}]}",
        "images[0].file",
      ),
      (
        "{\"category_ids\":[42],\"images\":[{\"image_id\":9,\"file\":\"/a.txt\"}]}",
        "images[0].file",
      ),
      (
        "{\"category_ids\":[42],\"images\":[{\"image_id\":9,\"file\":\"a//b.txt\"}]}",
        "images[0].file",
      ),
    ] {
    try @moondeteval.parse_yolo_manifest(source, dataset) catch {
      @moondeteval.InvalidInput(message) =>
        assert_true(message.contains(expected))
      _ => fail("wrong error")
    } noraise {
      _ => fail("invalid manifest accepted")
    }
  }
}
