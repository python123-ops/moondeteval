///|
priv struct CocoMaskAnnotation {
  id : Json
  image_id : Int
  category_id : Int
  segmentation : Json
  area : Double
  iscrowd : Json?
  ignore : Json?
} derive(FromJson)

///|
priv struct CocoMaskPrediction {
  image_id : Int
  category_id : Int
  segmentation : Json
  score : Double
} derive(FromJson)

///|
/// Reads compressed or uncompressed RLE annotations. Polygon arrays are rejected.
/// bbox is not required and does not affect mask scoring. Annotation area is kept.
pub fn parse_coco_mask_dataset(source : String) -> MaskDataset raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidInput("ground truth is not valid JSON")
  }
  let raw : CocoGroundTruthFile = @json.from_json(json) catch {
    error =>
      raise InvalidInput(
        "ground truth needs images, categories and annotations: " +
        error.to_string(),
      )
  }
  let images : Array[Image] = []
  let categories : Array[Category] = []
  let truths : Array[MaskGroundTruth] = []
  let image_ids : Map[Int, Image] = Map([])
  let category_ids : Map[Int, Bool] = Map([])
  let truth_ids : Map[Int64, Bool] = Map([])
  for index, entry in raw.images {
    let item = try {
      let image : CocoImage = @json.from_json(entry) catch {
        error => raise InvalidInput(error.to_string())
      }
      Image::new(image.id, image.width, image.height)
    } catch {
      error =>
        raise InvalidInput(
          "images[" + index.to_string() + "]: " + error.message(),
        )
    }
    if image_ids.contains(item.id) {
      raise InvalidInput(
        "images[" + index.to_string() + "].id duplicates " + item.id.to_string(),
      )
    }
    images.push(item)
    image_ids[item.id] = item
  }
  for index, entry in raw.categories {
    let item = try {
      let category : CocoCategory = @json.from_json(entry) catch {
        error => raise InvalidInput(error.to_string())
      }
      Category::new(category.id, category.name)
    } catch {
      error =>
        raise InvalidInput(
          "categories[" + index.to_string() + "]: " + error.message(),
        )
    }
    if category_ids.contains(item.id) {
      raise InvalidInput(
        "categories[" +
        index.to_string() +
        "].id duplicates " +
        item.id.to_string(),
      )
    }
    categories.push(item)
    category_ids[item.id] = true
  }
  for index, entry in raw.annotations {
    let location = "annotations[" + index.to_string() + "]"
    let item = try {
      let annotation : CocoMaskAnnotation = @json.from_json(entry) catch {
        error => raise InvalidInput(error.to_string())
      }
      MaskGroundTruth::new(
        parse_annotation_id(annotation.id, "id"),
        annotation.image_id,
        annotation.category_id,
        parse_rle_value(annotation.segmentation),
        area=annotation.area,
        iscrowd=parse_flag(annotation.iscrowd, "iscrowd"),
        ignore=parse_flag(annotation.ignore, "ignore"),
      )
    } catch {
      error => raise InvalidInput(location + ": " + error.message())
    }
    if truth_ids.contains(item.id()) {
      raise InvalidInput(location + ".id duplicates " + item.id().to_string())
    }
    match image_ids.get(item.image_id()) {
      Some(image) => validate_mask_canvas(item.mask(), image, location)
      None =>
        raise InvalidInput(location + ".image_id references unknown image")
    }
    if !category_ids.contains(item.category_id()) {
      raise InvalidInput(location + ".category_id references unknown category")
    }
    truths.push(item)
    truth_ids[item.id()] = true
  }
  MaskDataset::new(images, categories, truths)
}

///|
/// Stable detection IDs are zero-based input positions. bbox and supplied area
/// fields are ignored: segmentation pixel area controls unmatched area filtering.
pub fn parse_coco_mask_detections(
  source : String,
) -> Array[MaskDetection] raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidInput("detections are not valid JSON")
  }
  let raw : Array[Json] = @json.from_json(json) catch {
    error =>
      raise InvalidInput("detections must be an array: " + error.to_string())
  }
  let predictions : Array[MaskDetection] = []
  for index, entry in raw {
    let item = try {
      let prediction : CocoMaskPrediction = @json.from_json(entry) catch {
        error => raise InvalidInput(error.to_string())
      }
      MaskDetection::new(
        index,
        prediction.image_id,
        prediction.category_id,
        parse_rle_value(prediction.segmentation),
        prediction.score,
      )
    } catch {
      error =>
        raise InvalidInput(
          "detections[" + index.to_string() + "]: " + error.message(),
        )
    }
    predictions.push(item)
  }
  predictions
}
