///|
priv struct CocoImage {
  id : Int
  width : Int
  height : Int
} derive(FromJson)

///|
priv struct CocoCategory {
  id : Int
  name : String
} derive(FromJson)

///|
priv struct CocoAnnotation {
  id : Json
  image_id : Int
  category_id : Int
  bbox : Array[Double]
  area : Double
  iscrowd : Json?
  ignore : Json?
} derive(FromJson)

///|
priv struct CocoGroundTruthFile {
  images : Array[Json]
  categories : Array[Json]
  annotations : Array[Json]
} derive(FromJson)

///|
priv struct CocoPrediction {
  image_id : Int
  category_id : Int
  bbox : Array[Double]
  score : Double
} derive(FromJson)

///|
fn parse_box(
  coordinates : Array[Double],
  location : String,
) -> Box raise EvalError {
  if coordinates.length() != 4 {
    raise InvalidInput(location + ".bbox must contain exactly four numbers")
  }
  Box::from_xywh(coordinates[0], coordinates[1], coordinates[2], coordinates[3]) catch {
    error => raise InvalidInput(location + ".bbox: " + error.message())
  }
}

///|
fn parse_annotation_id(
  value : Json,
  location : String,
) -> Int64 raise EvalError {
  guard value is Json::Number(_, ..) else {
    raise InvalidInput(location + " must be a 64-bit integer JSON number")
  }
  let token = value.stringify()
  @json.from_json(Json::string(token)) catch {
    _ => raise InvalidInput(location + " must be a 64-bit integer JSON number")
  }
}

///|
fn parse_flag(value : Json?, location : String) -> Bool raise EvalError {
  match value {
    None => false
    Some(Json::True) => true
    Some(Json::False) => false
    Some(Json::Number(number, ..)) if number == 0.0 => false
    Some(Json::Number(number, ..)) if number == 1.0 => true
    _ => raise InvalidInput(location + " must be boolean or 0/1")
  }
}

///|
/// Parse the image, category, and annotation fields of a COCO ground-truth file.
pub fn parse_coco_dataset(source : String) -> Dataset raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidInput("ground truth is not valid JSON")
  }
  let raw : CocoGroundTruthFile = @json.from_json(json) catch {
    _ =>
      raise InvalidInput(
        "ground truth needs images, categories, and annotations with valid field types",
      )
  }
  let images : Array[Image] = []
  let categories : Array[Category] = []
  let truths : Array[GroundTruth] = []
  for index, entry in raw.images {
    let image : CocoImage = @json.from_json(entry) catch {
      _ => raise InvalidInput("images[\{index}] has invalid or missing fields")
    }
    let item = Image::new(image.id, image.width, image.height) catch {
      error => raise InvalidInput("images[\{index}]: " + error.message())
    }
    images.push(item)
  }
  for index, entry in raw.categories {
    let category : CocoCategory = @json.from_json(entry) catch {
      _ =>
        raise InvalidInput("categories[\{index}] has invalid or missing fields")
    }
    let item = Category::new(category.id, category.name) catch {
      error => raise InvalidInput("categories[\{index}]: " + error.message())
    }
    categories.push(item)
  }
  for index, entry in raw.annotations {
    let location = "annotations[\{index}]"
    let annotation : CocoAnnotation = @json.from_json(entry) catch {
      _ => raise InvalidInput(location + " has invalid or missing fields")
    }
    let bbox = parse_box(annotation.bbox, location)
    let item = GroundTruth::new(
      parse_annotation_id(annotation.id, location + ".id"),
      annotation.image_id,
      annotation.category_id,
      bbox,
      area=annotation.area,
      iscrowd=parse_flag(annotation.iscrowd, location + ".iscrowd"),
      ignore=parse_flag(annotation.ignore, location + ".ignore"),
    ) catch {
      error => raise InvalidInput(location + ": " + error.message())
    }
    truths.push(item)
  }
  Dataset::new(images, categories, truths)
}

///|
/// Parse standard COCO detections; their stable IDs are their zero-based positions.
pub fn parse_coco_detections(
  source : String,
) -> Array[Detection] raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidInput("detections are not valid JSON")
  }
  let raw : Array[Json] = @json.from_json(json) catch {
    _ =>
      raise InvalidInput(
        "detections must be an array of image_id, category_id, bbox, and score records",
      )
  }
  let predictions : Array[Detection] = []
  for index, entry in raw {
    let location = "detections[\{index}]"
    let prediction : CocoPrediction = @json.from_json(entry) catch {
      _ => raise InvalidInput(location + " has invalid or missing fields")
    }
    let bbox = parse_box(prediction.bbox, location)
    let item = Detection::new(
      index,
      prediction.image_id,
      prediction.category_id,
      bbox,
      prediction.score,
    ) catch {
      error => raise InvalidInput(location + ": " + error.message())
    }
    predictions.push(item)
  }
  predictions
}
