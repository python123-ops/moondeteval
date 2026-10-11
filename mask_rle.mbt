///|
/// A validated COCO mask RLE. Runs alternate background and foreground
/// pixels in column-major image order, starting with background.
pub struct CocoRle {
  height : Int
  width : Int
  counts : Array[Int]
  foreground_area : Int
}

///|
fn rle_pixel_count(height : Int, width : Int) -> Int64 raise EvalError {
  if height <= 0 || width <= 0 {
    raise InvalidInput("mask RLE height and width must be positive")
  }
  let pixels = height.to_int64() * width.to_int64()
  if pixels > 2147483647L {
    raise InvalidInput("mask RLE image exceeds supported pixel count")
  }
  pixels
}

///|
/// Creates an RLE without expanding it into a pixel array. The run lengths
/// must sum to height * width; an initial zero run represents a mask whose
/// first pixel is foreground. Dimensions are limited to Int-sized images.
pub fn CocoRle::new(
  height : Int,
  width : Int,
  counts : Array[Int],
) -> CocoRle raise EvalError {
  let pixels = rle_pixel_count(height, width)
  if counts.is_empty() {
    raise InvalidInput("mask RLE counts must not be empty")
  }
  let mut total = 0L
  let mut area = 0L
  for index, count in counts {
    if count < 0 || count.to_int64() > pixels - total {
      raise InvalidInput(
        "mask RLE has negative or excess run at index \{index}",
      )
    }
    total += count.to_int64()
    if index % 2 == 1 {
      area += count.to_int64()
    }
  }
  if total != pixels {
    raise InvalidInput("mask RLE run lengths do not cover the image")
  }
  { height, width, counts: counts.copy(), foreground_area: area.to_int(), }
}

///|
pub fn CocoRle::height(self : CocoRle) -> Int {
  self.height
}

///|
pub fn CocoRle::width(self : CocoRle) -> Int {
  self.width
}

///|
pub fn CocoRle::area(self : CocoRle) -> Int {
  self.foreground_area
}

///|
fn CocoRle::intersection(self : CocoRle, other : CocoRle) -> Int {
  let mut left_index = 0
  let mut right_index = 0
  let mut left_remaining = self.counts[0]
  let mut right_remaining = other.counts[0]
  let mut common = 0
  while left_index < self.counts.length() && right_index < other.counts.length() {
    if left_remaining == 0 {
      left_index += 1
      if left_index < self.counts.length() {
        left_remaining = self.counts[left_index]
      }
      continue
    }
    if right_remaining == 0 {
      right_index += 1
      if right_index < other.counts.length() {
        right_remaining = other.counts[right_index]
      }
      continue
    }
    let span = left_remaining.min(right_remaining)
    if left_index % 2 == 1 && right_index % 2 == 1 {
      common += span
    }
    left_remaining -= span
    right_remaining -= span
  }
  common
}

///|
/// Returns the mask IoU for equal-sized images. Empty masks have IoU zero.
pub fn CocoRle::iou(self : CocoRle, other : CocoRle) -> Double raise EvalError {
  if self.height != other.height || self.width != other.width {
    raise InvalidInput("mask RLE image dimensions differ")
  }
  let common = self.intersection(other).to_double()
  let union = self.foreground_area.to_double() +
    other.foreground_area.to_double() -
    common
  if union == 0.0 {
    0.0
  } else {
    common / union
  }
}

///|
/// COCO crowd overlap: self is the detection, other is a crowd ground truth.
/// The denominator is the detection area, not the union.
pub fn CocoRle::crowd_iou(
  self : CocoRle,
  other : CocoRle,
) -> Double raise EvalError {
  if self.height != other.height || self.width != other.width {
    raise InvalidInput("mask RLE image dimensions differ")
  }
  if self.foreground_area == 0 {
    0.0
  } else {
    self.intersection(other).to_double() / self.foreground_area.to_double()
  }
}
