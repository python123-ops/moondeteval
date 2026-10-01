///|
/// An axis-aligned rectangle in continuous pixel coordinates.
pub struct Box {
  x1 : Double
  y1 : Double
  x2 : Double
  y2 : Double
} derive(Debug, Eq)

///|
pub extend Box with Debug::{to_repr}

///|
pub extend Box with Eq::{equal, not_equal}

///|
pub(all) suberror EvalError {
  InvalidBox(String)
  InvalidInput(String)
  InvalidConfig(String)
} derive(Debug)

///|
pub extend EvalError with Debug::{to_repr}

///|
pub fn EvalError::message(self : EvalError) -> String {
  match self {
    InvalidBox(reason) => "invalid box: " + reason
    InvalidInput(reason) => "invalid input: " + reason
    InvalidConfig(reason) => "invalid configuration: " + reason
  }
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
/// Creates a nonempty box. Coordinates outside an image are allowed.
pub fn Box::new(
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
) -> Box raise EvalError {
  if !finite(x1) ||
    !finite(y1) ||
    !finite(x2) ||
    !finite(y2) ||
    x2 <= x1 ||
    y2 <= y1 {
    raise InvalidBox("expected finite coordinates with x2 > x1 and y2 > y1")
  }
  let width = x2 - x1
  let height = y2 - y1
  if !finite(width) || !finite(height) || !finite(width * height) {
    raise InvalidBox("box dimensions or area overflow")
  }
  { x1, y1, x2, y2, }
}

///|
/// Creates a box from COCO-style top-left coordinates and dimensions.
pub fn Box::from_xywh(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Box raise EvalError {
  Box::new(x, y, x + width, y + height)
}

///|
pub fn Box::to_xywh(self : Box) -> (Double, Double, Double, Double) {
  (self.x1, self.y1, self.x2 - self.x1, self.y2 - self.y1)
}

///|
pub fn Box::area(self : Box) -> Double {
  (self.x2 - self.x1) * (self.y2 - self.y1)
}

///|
/// Computes IoU for two ordinary (non-crowd) boxes.
pub fn Box::iou(self : Box, other : Box) -> Double {
  let width = (self.x2.min(other.x2) - self.x1.max(other.x1)).max(0.0)
  let height = (self.y2.min(other.y2) - self.y1.max(other.y1)).max(0.0)
  let intersection = width * height
  if intersection == 0.0 {
    return 0.0
  }
  let left_area = self.area()
  let right_area = other.area()
  let scale = left_area.max(right_area)
  let scaled_intersection = intersection / scale
  scaled_intersection /
  (left_area / scale + right_area / scale - scaled_intersection)
}
