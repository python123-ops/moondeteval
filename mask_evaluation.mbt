///|
/// An instance mask with COCO annotation area (which may differ from pixel area).
pub struct MaskGroundTruth {
  value : GroundTruth
}

///|
pub fn MaskGroundTruth::new(
  id : Int64,
  image_id : Int32,
  category_id : Int32,
  mask : CocoRle,
  area~ : Double,
  iscrowd~ : Bool = false,
  ignore~ : Bool = false,
) -> MaskGroundTruth raise EvalError {
  let value = GroundTruth::new(
    id,
    image_id,
    category_id,
    Box::from_xywh(
      0.0,
      0.0,
      mask.width().to_double(),
      mask.height().to_double(),
    ),
    area~,
    iscrowd~,
    ignore~,
  )
  { value: { ..value, mask: Some(mask), }, }
}

///|
pub fn MaskGroundTruth::id(self : MaskGroundTruth) -> Int64 {
  self.value.id
}

///|
pub fn MaskGroundTruth::image_id(self : MaskGroundTruth) -> Int32 {
  self.value.image_id
}

///|
pub fn MaskGroundTruth::category_id(self : MaskGroundTruth) -> Int32 {
  self.value.category_id
}

///|
pub fn MaskGroundTruth::mask(self : MaskGroundTruth) -> CocoRle {
  self.value.mask.unwrap()
}

///|
pub fn MaskGroundTruth::area(self : MaskGroundTruth) -> Double {
  self.value.area
}

///|
pub fn MaskGroundTruth::iscrowd(self : MaskGroundTruth) -> Bool {
  self.value.iscrowd
}

///|
pub fn MaskGroundTruth::ignore(self : MaskGroundTruth) -> Bool {
  self.value.ignore
}

///|
/// A scored mask. Detection area is always the RLE foreground pixel count.
pub struct MaskDetection {
  value : Detection
}

///|
pub fn MaskDetection::new(
  id : Int32,
  image_id : Int32,
  category_id : Int32,
  mask : CocoRle,
  score : Double,
) -> MaskDetection raise EvalError {
  let value = Detection::new(
    id,
    image_id,
    category_id,
    Box::from_xywh(
      0.0,
      0.0,
      mask.width().to_double(),
      mask.height().to_double(),
    ),
    score,
  )
  { value: { ..value, mask: Some(mask), }, }
}

///|
pub fn MaskDetection::id(self : MaskDetection) -> Int32 {
  self.value.id
}

///|
pub fn MaskDetection::image_id(self : MaskDetection) -> Int32 {
  self.value.image_id
}

///|
pub fn MaskDetection::category_id(self : MaskDetection) -> Int32 {
  self.value.category_id
}

///|
pub fn MaskDetection::mask(self : MaskDetection) -> CocoRle {
  self.value.mask.unwrap()
}

///|
pub fn MaskDetection::score(self : MaskDetection) -> Double {
  self.value.score
}

///|
/// Mask inputs are separated from bounding boxes to prevent mixed geometry.
pub struct MaskDataset {
  value : Dataset
}

///|
fn validate_mask_canvas(
  mask : CocoRle,
  image : Image,
  location : String,
) -> Unit raise EvalError {
  if mask.width() != image.width || mask.height() != image.height {
    raise InvalidInput(
      location + " mask dimensions differ from image " + image.id.to_string(),
    )
  }
}

///|
pub fn MaskDataset::new(
  images : Array[Image],
  categories : Array[Category],
  truths : Array[MaskGroundTruth],
) -> MaskDataset raise EvalError {
  let value = Dataset::new(
    images,
    categories,
    truths.map(fn(item) { item.value }),
  )
  let images_by_id : Map[Int32, Image] = Map([])
  for image in value.images {
    images_by_id[image.id] = image
  }
  for truth in truths {
    validate_mask_canvas(
      truth.mask(),
      images_by_id[truth.image_id()],
      "ground-truth " + truth.id().to_string(),
    )
  }
  { value, }
}

///|
pub fn MaskDataset::images(self : MaskDataset) -> Array[Image] {
  self.value.images()
}

///|
pub fn MaskDataset::categories(self : MaskDataset) -> Array[Category] {
  self.value.categories()
}

///|
pub fn MaskDataset::truths(self : MaskDataset) -> Array[MaskGroundTruth] {
  self.value.truths.map(fn(value) { { value, } })
}

///|
/// COCO segm defaults: ten IoUs, three area bins, maxDets 1/10/100, 101 recall points.
pub fn evaluate_masks(
  dataset : MaskDataset,
  predictions : Array[MaskDetection],
) -> EvaluationReport raise EvalError {
  evaluate_masks_with_config(dataset, predictions, EvalConfig::coco())
}

///|
/// Optional diagnostics and PR curves use mask overlap. COCO default ignore
/// handling uses iscrowd; respect_explicit remains an opt-in extension.
pub fn evaluate_masks_with_config(
  dataset : MaskDataset,
  predictions : Array[MaskDetection],
  config : EvalConfig,
) -> EvaluationReport raise EvalError {
  let images : Map[Int32, Image] = Map([])
  let categories : Map[Int32, Bool] = Map([])
  for image in dataset.value.images {
    images[image.id] = image
  }
  for category in dataset.value.categories {
    categories[category.id] = true
  }
  for index, prediction in predictions {
    let location = "detections[" + index.to_string() + "]"
    match images.get(prediction.image_id()) {
      Some(image) => validate_mask_canvas(prediction.mask(), image, location)
      None =>
        raise InvalidInput(location + ".image_id references unknown image")
    }
    if !categories.contains(prediction.category_id()) {
      raise InvalidInput(location + ".category_id references unknown category")
    }
  }
  let mask_config = if config.ignore_policy == "coco_bbox" {
    { ..config, ignore_policy: "coco_segm", }
  } else {
    config
  }
  evaluate_internal(
    dataset.value,
    predictions.map(fn(item) { item.value }),
    mask_config,
    iou_type="segm",
  )
}

///|
pub fn compare_mask_predictions(
  dataset : MaskDataset,
  baseline : Array[MaskDetection],
  candidate : Array[MaskDetection],
) -> ComparisonReport raise EvalError {
  compare_mask_predictions_with_config(
    dataset,
    baseline,
    candidate,
    EvalConfig::coco(),
  )
}

///|
pub fn compare_mask_predictions_with_config(
  dataset : MaskDataset,
  baseline : Array[MaskDetection],
  candidate : Array[MaskDetection],
  config : EvalConfig,
) -> ComparisonReport raise EvalError {
  compare_reports(
    evaluate_masks_with_config(dataset, baseline, config),
    evaluate_masks_with_config(dataset, candidate, config),
  )
}
