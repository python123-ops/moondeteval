///|
/// Split a YOLO row on Unicode whitespace without accepting empty columns.
fn yolo_fields(line : StringView) -> Array[String] {
  let fields : Array[String] = []
  let current = StringBuilder()
  for character in line.iter() {
    if character.is_whitespace() {
      if !current.is_empty() {
        fields.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(character)
    }
  }
  if !current.is_empty() {
    fields.push(current.to_string())
  }
  fields
}

///|
fn yolo_number(value : String, location : String) -> Double raise EvalError {
  let number = @string.parse_double(value) catch {
    _ => raise InvalidInput(location + " must be a number")
  }
  if !finite(number) {
    raise InvalidInput(location + " must be finite")
  }
  number
}

///|
fn yolo_fraction(
  value : String,
  location : String,
  positive : Bool,
) -> Double raise EvalError {
  let number = yolo_number(value, location)
  if number > 1.0 || number < 0.0 || (positive && number == 0.0) {
    let range = if positive { "(0,1]" } else { "[0,1]" }
    raise InvalidInput(location + " must be normalized to " + range)
  }
  number
}

///|
/// Parse six-column YOLO prediction TXT for one image:
/// class_index center_x center_y width height confidence.
/// Coordinates are normalized; category_ids maps zero-based YOLO class indices
/// to category IDs in the dataset. Blank lines are ignored. IDs are assigned
/// from first_detection_id in row order, excluding blank lines.
/// Derived boxes may cross image bounds and are reported by evaluation warnings.
pub fn parse_yolo_detections(
  source : String,
  dataset : Dataset,
  image_id : Int,
  category_ids : Array[Int],
  first_detection_id? : Int = 0,
) -> Array[Detection] raise EvalError {
  let mut selected_image : Image? = None
  for image in dataset.images {
    if image.id == image_id {
      selected_image = Some(image)
      break
    }
  }
  let image = match selected_image {
    Some(value) => value
    None =>
      raise InvalidInput("YOLO image_id \{image_id} is not in the dataset")
  }
  for index, category_id in category_ids {
    let mut known = false
    for category in dataset.categories {
      if category.id == category_id {
        known = true
        break
      }
    }
    if !known {
      raise InvalidInput(
        "YOLO category_ids[\{index}] \{category_id} is not in the dataset",
      )
    }
  }
  let detections : Array[Detection] = []
  let mut line_number = 0
  for line in source.split("\n") {
    line_number += 1
    let fields = yolo_fields(line)
    if fields.is_empty() {
      continue
    }
    let location = "YOLO line \{line_number}"
    if fields.length() != 6 {
      raise InvalidInput(
        location + " must have six columns: class cx cy w h score",
      )
    }
    let class_index = @string.parse_int(fields[0], base=10) catch {
      _ => raise InvalidInput(location + " class_index must be an integer")
    }
    if class_index < 0 || class_index >= category_ids.length() {
      raise InvalidInput(location + " class_index \{class_index} is not mapped")
    }
    let center_x = yolo_fraction(fields[1], location + " center_x", false)
    let center_y = yolo_fraction(fields[2], location + " center_y", false)
    let width = yolo_fraction(fields[3], location + " width", true)
    let height = yolo_fraction(fields[4], location + " height", true)
    let score = yolo_fraction(fields[5], location + " score", false)
    let next_id = first_detection_id.to_int64() + detections.length().to_int64()
    if next_id > 2147483647L {
      raise InvalidInput(location + " detection ID exceeds Int range")
    }
    let x1 = (center_x - width / 2.0) * image.width.to_double()
    let y1 = (center_y - height / 2.0) * image.height.to_double()
    let x2 = (center_x + width / 2.0) * image.width.to_double()
    let y2 = (center_y + height / 2.0) * image.height.to_double()
    let box = Box::new(x1, y1, x2, y2) catch {
      error => raise InvalidInput(location + " box: " + error.message())
    }
    detections.push(
      Detection::new(
        next_id.to_int(),
        image_id,
        category_ids[class_index],
        box,
        score,
      ),
    )
  }
  detections
}
