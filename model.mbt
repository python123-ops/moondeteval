///|
/// An image declared by the ground-truth dataset.
pub struct Image {
  id : Int
  width : Int
  height : Int
} derive(Debug, Eq)

///|
pub extend Image with Debug::{to_repr}

///|
pub extend Image with Eq::{equal, not_equal}

///|
pub fn Image::new(id : Int, width : Int, height : Int) -> Image raise EvalError {
  if width <= 0 || height <= 0 {
    raise InvalidInput("image width and height must be positive")
  }
  { id, width, height, }
}

///|
pub fn Image::id(self : Image) -> Int {
  self.id
}

///|
pub fn Image::width(self : Image) -> Int {
  self.width
}

///|
pub fn Image::height(self : Image) -> Int {
  self.height
}

///|
pub struct Category {
  id : Int
  name : String
} derive(Debug, Eq)

///|
pub extend Category with Debug::{to_repr}

///|
pub extend Category with Eq::{equal, not_equal}

///|
pub fn Category::new(id : Int, name : String) -> Category raise EvalError {
  if name.is_empty() {
    raise InvalidInput("category name must be nonempty")
  }
  { id, name, }
}

///|
pub fn Category::id(self : Category) -> Int {
  self.id
}

///|
pub fn Category::name(self : Category) -> String {
  self.name
}

///|
/// A validated COCO-style ground-truth object.
pub struct GroundTruth {
  id : Int64
  image_id : Int
  category_id : Int
  bbox : Box
  area : Double
  iscrowd : Bool
  ignore : Bool
} derive(Debug, Eq)

///|
pub extend GroundTruth with Debug::{to_repr}

///|
pub extend GroundTruth with Eq::{equal, not_equal}

///|
pub fn GroundTruth::new(
  id : Int64,
  image_id : Int,
  category_id : Int,
  bbox : Box,
  area~ : Double,
  iscrowd? : Bool = false,
  ignore? : Bool = false,
) -> GroundTruth raise EvalError {
  if !finite(area) || area < 0.0 {
    raise InvalidInput("ground-truth area must be finite and nonnegative")
  }
  { id, image_id, category_id, bbox, area, iscrowd, ignore, }
}

///|
pub fn GroundTruth::id(self : GroundTruth) -> Int64 {
  self.id
}

///|
pub fn GroundTruth::image_id(self : GroundTruth) -> Int {
  self.image_id
}

///|
pub fn GroundTruth::category_id(self : GroundTruth) -> Int {
  self.category_id
}

///|
pub fn GroundTruth::bbox(self : GroundTruth) -> Box {
  self.bbox
}

///|
pub fn GroundTruth::area(self : GroundTruth) -> Double {
  self.area
}

///|
pub fn GroundTruth::iscrowd(self : GroundTruth) -> Bool {
  self.iscrowd
}

///|
pub fn GroundTruth::ignore(self : GroundTruth) -> Bool {
  self.ignore
}

///|
/// A scored detector output. `id` is stable within one evaluation.
pub struct Detection {
  id : Int
  image_id : Int
  category_id : Int
  bbox : Box
  score : Double
} derive(Debug, Eq)

///|
pub extend Detection with Debug::{to_repr}

///|
pub extend Detection with Eq::{equal, not_equal}

///|
pub fn Detection::new(
  id : Int,
  image_id : Int,
  category_id : Int,
  bbox : Box,
  score : Double,
) -> Detection raise EvalError {
  if !finite(score) {
    raise InvalidInput("detection score must be finite")
  }
  { id, image_id, category_id, bbox, score, }
}

///|
pub fn Detection::id(self : Detection) -> Int {
  self.id
}

///|
pub fn Detection::image_id(self : Detection) -> Int {
  self.image_id
}

///|
pub fn Detection::category_id(self : Detection) -> Int {
  self.category_id
}

///|
pub fn Detection::bbox(self : Detection) -> Box {
  self.bbox
}

///|
pub fn Detection::score(self : Detection) -> Double {
  self.score
}

///|
/// A reusable, immutable evaluation input.
pub struct Dataset {
  images : Array[Image]
  categories : Array[Category]
  truths : Array[GroundTruth]
}

///|
pub fn Dataset::new(
  images : Array[Image],
  categories : Array[Category],
  truths : Array[GroundTruth],
) -> Dataset raise EvalError {
  let image_ids : Map[Int, Bool] = Map([])
  let category_ids : Map[Int, Bool] = Map([])
  let truth_ids : Map[Int64, Bool] = Map([])
  for image in images {
    if image_ids.contains(image.id) {
      raise InvalidInput("duplicate image id \{image.id}")
    }
    image_ids[image.id] = true
  }
  for category in categories {
    if category_ids.contains(category.id) {
      raise InvalidInput("duplicate category id \{category.id}")
    }
    category_ids[category.id] = true
  }
  for truth in truths {
    if truth_ids.contains(truth.id) {
      raise InvalidInput("duplicate ground-truth id \{truth.id}")
    }
    if !image_ids.contains(truth.image_id) ||
      !category_ids.contains(truth.category_id) {
      raise InvalidInput(
        "ground-truth \{truth.id} references unknown image or category",
      )
    }
    truth_ids[truth.id] = true
  }
  {
    images: images.copy(),
    categories: categories.copy(),
    truths: truths.copy(),
  }
}

///|
pub fn Dataset::images(self : Dataset) -> Array[Image] {
  self.images.copy()
}

///|
pub fn Dataset::categories(self : Dataset) -> Array[Category] {
  self.categories.copy()
}

///|
pub fn Dataset::truths(self : Dataset) -> Array[GroundTruth] {
  self.truths.copy()
}
