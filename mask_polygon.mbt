///|
// COCO boundary quantization and event encoding adapted from rleFrPoly in
// cocodataset/cocoapi/common/maskApi.c. See THIRD_PARTY_NOTICES.md (BSD-2-Clause).
// Boundary samples are streamed: no dense image or boundary-point array.
priv struct PolygonPoint {
  x : Int64
  y : Int64
} derive(Eq)

///|
fn polygon_coordinate(
  value : Double,
  location : String,
) -> Int64 raise EvalError {
  let scaled = value * 5.0 + 0.5
  if !finite(value) ||
    !finite(scaled) ||
    scaled < -2147483648.0 ||
    scaled > 2147483647.0 {
    raise InvalidInput(
      location + " must be finite and fit COCO scaled Int coordinates",
    )
  }
  scaled.trunc().to_int64()
}

///|
fn polygon_event(
  previous : PolygonPoint,
  current : PolygonPoint,
  height : Int32,
  width : Int32,
) -> Int32? {
  if previous.x == current.x {
    return None
  }
  let boundary_x = if current.x < previous.x {
    current.x
  } else {
    current.x - 1L
  }
  let x = (boundary_x.to_double() + 0.5) / 5.0 - 0.5
  if x.floor() != x || x < 0.0 || x > width.to_double() - 1.0 {
    return None
  }
  let y = ((previous.y.min(current.y).to_double() + 0.5) / 5.0 - 0.5)
    .max(0.0)
    .min(height.to_double())
    .ceil()
  Some((x.to_int64() * height.to_int64() + y.to_int64()).to_int())
}

///|
fn rasterize_polygon(
  height : Int32,
  width : Int32,
  points : Array[PolygonPoint],
) -> CocoRle raise EvalError {
  let pixels = rle_pixel_count(height, width).to_int()
  if points.length() < 3 {
    return CocoRle::new(height, width, [pixels])
  }
  let events : Array[Int32] = []
  let mut previous : PolygonPoint? = None
  for index in 0..<points.length() {
    let first = points[index]
    let last = points[(index + 1) % points.length()]
    let dx = (last.x - first.x).abs()
    let dy = (last.y - first.y).abs()
    if dx == 0L && dy == 0L {
      continue
    }
    let flip = (dx >= dy && first.x > last.x) || (dx < dy && first.y > last.y)
    let start = if flip { last } else { first }
    let end = if flip { first } else { last }
    let steps = dx.max(dy).to_int()
    let slope = if dx >= dy {
      (end.y - start.y).to_double() / dx.to_double()
    } else {
      (end.x - start.x).to_double() / dy.to_double()
    }
    for offset in 0..<=steps {
      let distance = (if flip { steps - offset } else { offset }).to_int64()
      let current = if dx >= dy {
        PolygonPoint::{
          x: start.x + distance,
          y: (start.y.to_double() + slope * distance.to_double() + 0.5)
          .trunc()
          .to_int64(),
        }
      } else {
        PolygonPoint::{
          x: (start.x.to_double() + slope * distance.to_double() + 0.5)
          .trunc()
          .to_int64(),
          y: start.y + distance,
        }
      }
      match previous {
        Some(point) =>
          match polygon_event(point, current, height, width) {
            Some(event) => events.push(event)
            None => ()
          }
        None => ()
      }
      previous = Some(current)
    }
  }
  events.push(pixels)
  events.sort()
  let counts = [events[0]]
  let mut index = 1
  while index < events.length() {
    let span = events[index] - events[index - 1]
    if span > 0 {
      counts.push(span)
      index += 1
    } else {
      // Coincident boundary crossings toggle twice and cancel.
      index += 1
      if index < events.length() {
        counts[counts.length() - 1] += events[index] - events[index - 1]
        index += 1
      }
    }
  }
  CocoRle::new(height, width, counts)
}

///|
fn polygon_union(
  left : CocoRle,
  right : CocoRle,
  remaining : Int32,
) -> (CocoRle, Int32) raise EvalError {
  let counts = [0]
  let mut active = false
  let mut left_index = 0
  let mut right_index = 0
  let mut left_remaining = left.counts[0]
  let mut right_remaining = right.counts[0]
  let mut work = 0
  while left_index < left.counts.length() && right_index < right.counts.length() {
    work += 1
    if work > remaining {
      raise InvalidInput("polygon RLE union exceeds 2000000 run steps per mask")
    }
    if left_remaining == 0 {
      left_index += 1
      if left_index < left.counts.length() {
        left_remaining = left.counts[left_index]
      }
      continue
    }
    if right_remaining == 0 {
      right_index += 1
      if right_index < right.counts.length() {
        right_remaining = right.counts[right_index]
      }
      continue
    }
    let foreground = left_index % 2 == 1 || right_index % 2 == 1
    let span = left_remaining.min(right_remaining)
    if foreground == active {
      counts[counts.length() - 1] += span
    } else {
      counts.push(span)
      active = foreground
    }
    left_remaining -= span
    right_remaining -= span
  }
  (CocoRle::new(left.height, left.width, counts), work)
}

///|
/// Rasterizes COCO polygon rings and unions them into one instance mask.
/// Rings contain >=3 x/y pairs; winding does not create holes. Empty ring lists
/// are invalid. Degenerate rings may yield empty masks. Uses COCO's 5x boundary
/// quantization. Limits: 100000 total vertices, 2000000 boundary samples and
/// 2000000 union run steps per mask; scaled coordinates fit signed 32-bit Int.
pub fn CocoRle::from_polygons(
  height : Int32,
  width : Int32,
  polygons : Array[Array[Double]],
) -> CocoRle raise EvalError {
  let _ = rle_pixel_count(height, width)
  if polygons.is_empty() {
    raise InvalidInput("segmentation polygons must contain at least one ring")
  }
  let rings : Array[Array[PolygonPoint]] = []
  let mut vertices = 0
  let mut samples = 0L
  for ring_index, coordinates in polygons {
    let location = "segmentation[" + ring_index.to_string() + "]"
    if coordinates.length() < 6 || coordinates.length() % 2 != 0 {
      raise InvalidInput(location + " must contain at least three x/y pairs")
    }
    if coordinates.length() / 2 > 100000 - vertices {
      raise InvalidInput(
        "segmentation exceeds 100000 polygon vertices per mask",
      )
    }
    vertices += coordinates.length() / 2
    let points : Array[PolygonPoint] = []
    for index in 0..<(coordinates.length() / 2) {
      let point = PolygonPoint::{
        x: polygon_coordinate(
          coordinates[index * 2],
          location + "[" + (index * 2).to_string() + "]",
        ),
        y: polygon_coordinate(
          coordinates[index * 2 + 1],
          location + "[" + (index * 2 + 1).to_string() + "]",
        ),
      }
      if points.is_empty() || points[points.length() - 1] != point {
        points.push(point)
      }
    }
    if points.length() > 1 && points[0] == points[points.length() - 1] {
      points.pop() |> ignore
    }
    for index in 0..<points.length() {
      let next = points[(index + 1) % points.length()]
      samples += (points[index].x - next.x)
        .abs()
        .max((points[index].y - next.y).abs()) +
        1L
      if samples > 2000000L {
        raise InvalidInput(
          "segmentation exceeds 2000000 polygon boundary samples per mask",
        )
      }
    }
    rings.push(points)
  }
  let mut result = rasterize_polygon(height, width, rings[0])
  let mut union_work = 0
  for index in 1..<rings.length() {
    let (combined, work) = polygon_union(
      result,
      rasterize_polygon(height, width, rings[index]),
      2000000 - union_work,
    )
    result = combined
    union_work += work
  }
  result
}

///|
fn parse_segmentation_value(
  value : Json,
  height : Int32,
  width : Int32,
) -> CocoRle raise EvalError {
  let mask = match value {
    Array(values) => {
      let polygons : Array[Array[Double]] = []
      let mut vertices = 0
      for index, ring in values {
        let location = "segmentation[" + index.to_string() + "]"
        let entries = match ring {
          Array(entries) => entries
          _ => raise InvalidInput(location + " must be an array of numbers")
        }
        if entries.length() / 2 > 100000 - vertices {
          raise InvalidInput(
            "segmentation exceeds 100000 polygon vertices per mask",
          )
        }
        vertices += entries.length() / 2
        let coordinates : Array[Double] = []
        for coordinate_index, entry in entries {
          match entry {
            Number(value, ..) => coordinates.push(value)
            _ =>
              raise InvalidInput(
                location +
                "[" +
                coordinate_index.to_string() +
                "] must be a number",
              )
          }
        }
        polygons.push(coordinates)
      }
      CocoRle::from_polygons(height, width, polygons)
    }
    _ => parse_rle_value(value)
  }
  if mask.height != height || mask.width != width {
    raise InvalidInput("segmentation RLE dimensions differ from image")
  }
  mask
}

///|
/// Parses a COCO segmentation RLE object or array of polygon rings, using the
/// declared image dimensions. RLE sizes must agree; polygon rings are unioned.
pub fn parse_coco_segmentation(
  source : String,
  height : Int32,
  width : Int32,
) -> CocoRle raise EvalError {
  let value = @json.parse(source) catch {
    _ => raise InvalidInput("segmentation is not valid JSON")
  }
  parse_segmentation_value(value, height, width)
}
