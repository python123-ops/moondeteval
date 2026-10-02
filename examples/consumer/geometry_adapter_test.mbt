///|
test "August geometry rectangle becomes October evaluation detection" {
  let source = @geometry.Rect2::new(
    min=@geometry.Point2::new(x=0.0, y=0.0),
    max=@geometry.Point2::new(x=10.0, y=10.0),
  )
  let from = [
    source.min,
    @geometry.Point2::new(x=10.0, y=0.0),
    source.max,
    @geometry.Point2::new(x=0.0, y=10.0),
  ]
  let to = [
    @geometry.Point2::new(x=20.0, y=30.0),
    @geometry.Point2::new(x=40.0, y=30.0),
    @geometry.Point2::new(x=40.0, y=50.0),
    @geometry.Point2::new(x=20.0, y=50.0),
  ]
  let h = @multiview.estimate_homography_from_four(from, to)
  let mapped = @consumer.warp_geometry_rect_to_box(source, h)
  let (x, y, width, height) = mapped.to_xywh()
  assert_true((x - 20.0).abs() < 0.000000001)
  assert_true((y - 30.0).abs() < 0.000000001)
  assert_true((width - 20.0).abs() < 0.000000001)
  assert_true((height - 20.0).abs() < 0.000000001)
  let truth = @moondeteval.Box::from_xywh(20.0, 30.0, 20.0, 20.0)
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 100, 100)],
    [@moondeteval.Category::new(7, "object")],
    [@moondeteval.GroundTruth::new(10, 1, 7, truth, area=400.0)],
  )
  let detection = @moondeteval.Detection::new(0, 1, 7, mapped, 0.9)
  assert_eq(@moondeteval.evaluate(dataset, [detection]).summary().ap50(), 1.0)
}

///|
test "geometry bridge rejects horizon crossing and empty rectangles" {
  let rect = @geometry.Rect2::new(
    min=@geometry.Point2::new(x=0.0, y=0.0),
    max=@geometry.Point2::new(x=10.0, y=10.0),
  )
  let crossing = @multiview.Homography::new(matrix=@geometry.Mat3::{
    m00: 1.0,
    m01: 0.0,
    m02: 0.0,
    m10: 0.0,
    m11: 1.0,
    m12: 0.0,
    m20: 0.1,
    m21: 0.0,
    m22: -0.5,
  })
  try @consumer.warp_geometry_rect_to_box(rect, crossing) catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("horizon"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("crossing accepted")
  }
  let flat = @geometry.Rect2::new(
    min=@geometry.Point2::new(x=0.0, y=0.0),
    max=@geometry.Point2::new(x=0.0, y=10.0),
  )
  try @consumer.geometry_rect_to_box(flat) catch {
    @moondeteval.InvalidBox(_) => ()
    _ => fail("wrong error")
  } noraise {
    _ => fail("empty box accepted")
  }
}

///|
test "geometry bridge encloses all corners after a slanted transform" {
  let rect = @geometry.Rect2::new(
    min=@geometry.Point2::new(x=0.0, y=0.0),
    max=@geometry.Point2::new(x=10.0, y=10.0),
  )
  let slanted = @multiview.Homography::new(matrix=@geometry.Mat3::{
    m00: 1.0,
    m01: -1.0,
    m02: 20.0,
    m10: 1.0,
    m11: 1.0,
    m12: 30.0,
    m20: 0.0,
    m21: 0.0,
    m22: 1.0,
  })
  let mapped = @consumer.warp_geometry_rect_to_box(rect, slanted)
  assert_eq(mapped.to_xywh(), (10.0, 30.0, 20.0, 20.0))
}
