///|
priv struct CocoMaskAnnotation {
  id : Json
  image_id : Int32
  category_id : Int32
  segmentation : Json
  area : Double
  iscrowd : Json?
  ignore : Json?
} derive(FromJson)

///|
priv struct CocoMaskPrediction {
  image_id : Int32
  category_id : Int32
  segmentation : Json
  score : Double
} derive(FromJson)

///|
/// Reads compressed/uncompressed RLE or polygon-ring annotations.
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
  let image_ids : Map[Int32, Image] = Map([])
  let category_ids : Map[Int32, Bool] = Map([])
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
      let image = match image_ids.get(annotation.image_id) {
        Some(image) => image
        None => raise InvalidInput("image_id references unknown image")
      }
      MaskGroundTruth::new(
        parse_annotation_id(annotation.id, "id"),
        annotation.image_id,
        annotation.category_id,
        parse_segmentation_value(
          annotation.segmentation,
          image.height,
          image.width,
        ),
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
/// This original entry point accepts RLE only. For polygons, use the dataset-aware
/// entry point below so canvas size comes from the declared image.
pub fn parse_coco_mask_detections(
  source : String,
) -> Array[MaskDetection] raise EvalError {
  parse_mask_predictions(source, None)
}

///|
/// Reads polygon or RLE predictions, validating references and canvas sizes
/// against the same ground-truth dataset used for evaluation.
pub fn parse_coco_mask_detections_with_dataset(
  source : String,
  dataset : MaskDataset,
) -> Array[MaskDetection] raise EvalError {
  parse_mask_predictions(source, Some(dataset))
}

///|
fn parse_mask_predictions(
  source : String,
  dataset : MaskDataset?,
) -> Array[MaskDetection] raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidInput("detections are not valid JSON")
  }
  let raw : Array[Json] = @json.from_json(json) catch {
    error =>
      raise InvalidInput("detections must be an array: " + error.to_string())
  }
  let predictions : Array[MaskDetection] = []
  let images : Map[Int32, Image] = Map([])
  let categories : Map[Int32, Bool] = Map([])
  match dataset {
    Some(value) => {
      for image in value.images() {
        images[image.id] = image
      }
      for category in value.categories() {
        categories[category.id] = true
      }
    }
    None => ()
  }
  for index, entry in raw {
    let item = try {
      let prediction : CocoMaskPrediction = @json.from_json(entry) catch {
        error => raise InvalidInput(error.to_string())
      }
      let mask = match dataset {
        Some(_) => {
          let image = match images.get(prediction.image_id) {
            Some(image) => image
            None => raise InvalidInput("image_id references unknown image")
          }
          if !categories.contains(prediction.category_id) {
            raise InvalidInput("category_id references unknown category")
          }
          parse_segmentation_value(
            prediction.segmentation,
            image.height,
            image.width,
          )
        }
        None => {
          if prediction.segmentation is Array(_) {
            raise InvalidInput(
              "polygon predictions require image dimensions; use parse_coco_mask_detections_with_dataset",
            )
          }
          parse_rle_value(prediction.segmentation)
        }
      }
      MaskDetection::new(
        index,
        prediction.image_id,
        prediction.category_id,
        mask,
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
