///|
/// Convert a geometry rectangle to the evaluator's continuous pixel box.
/// Geometry permits zero-area rectangles; the evaluator rejects them.
pub fn geometry_rect_to_box(
  rect : @geometry.Rect2,
) -> @moondeteval.Box raise @moondeteval.EvalError {
  @moondeteval.Box::new(rect.min.x, rect.min.y, rect.max.x, rect.max.y)
}

///|
/// Map a source-image rectangle into a target image before detection evaluation.
/// The envelope of four transformed corners is exact if the projective horizon
/// does not cross the rectangle. No clipping to the target image is performed.
pub fn warp_geometry_rect_to_box(
  rect : @geometry.Rect2,
  homography : @multiview.Homography,
) -> @moondeteval.Box raise @moondeteval.EvalError {
  let corners = [
    rect.min,
    @geometry.Point2::new(x=rect.max.x, y=rect.min.y),
    rect.max,
    @geometry.Point2::new(x=rect.min.x, y=rect.max.y),
  ]
  let mut sign = 0
  let mapped : Array[@geometry.Point2] = []
  for corner in corners {
    let denominator = homography.matrix.m20 * corner.x +
      homography.matrix.m21 * corner.y +
      homography.matrix.m22
    if denominator.is_nan() ||
      denominator.is_inf() ||
      denominator.abs() <= 0.000000000001 {
      raise @moondeteval.InvalidInput(
        "homography crosses the rectangle horizon",
      )
    }
    let current_sign = if denominator > 0.0 { 1 } else { -1 }
    if sign != 0 && current_sign != sign {
      raise @moondeteval.InvalidInput(
        "homography crosses the rectangle horizon",
      )
    }
    sign = current_sign
    let projected = homography.apply(corner) catch {
      _ =>
        raise @moondeteval.InvalidInput("homography cannot project rectangle")
    }
    if projected.x.is_nan() ||
      projected.x.is_inf() ||
      projected.y.is_nan() ||
      projected.y.is_inf() {
      raise @moondeteval.InvalidInput(
        "homography produced nonfinite coordinates",
      )
    }
    mapped.push(projected)
  }
  let envelope = @geometry.rect2_from_points(mapped) catch {
    _ =>
      raise @moondeteval.InvalidInput("homography produced invalid rectangle")
  }
  geometry_rect_to_box(envelope)
}
