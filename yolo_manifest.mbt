///|
priv struct YoloManifestJson {
  category_ids : Array[Int]
  images : Array[Json]
} derive(FromJson)

///|
priv struct YoloFileJson {
  image_id : Int
  file : String
} derive(FromJson)

///|
/// One TXT file, relative to its manifest directory.
pub struct YoloFile {
  image_id : Int
  file : String
}

///|
pub fn YoloFile::image_id(self : YoloFile) -> Int {
  self.image_id
}

///|
pub fn YoloFile::file(self : YoloFile) -> String {
  self.file
}

///|
/// Class mapping and ordered per-image prediction files.
pub struct YoloManifest {
  category_ids : Array[Int]
  images : Array[YoloFile]
}

///|
pub fn YoloManifest::category_ids(self : YoloManifest) -> Array[Int] {
  self.category_ids.copy()
}

///|
pub fn YoloManifest::images(self : YoloManifest) -> Array[YoloFile] {
  self.images.copy()
}

///|
fn valid_yolo_file_path(path : String) -> Bool {
  if path.is_empty() ||
    path.has_prefix("/") ||
    path.contains("\\") ||
    path.contains(":") {
    return false
  }
  for part in path.split("/") {
    if part == "" || part == "." || part == ".." {
      return false
    }
  }
  true
}

///|
/// Parse a multi-image YOLO manifest against a ground-truth dataset.
/// Relative paths use forward slashes; . and .. segments are rejected.
pub fn parse_yolo_manifest(
  source : String,
  dataset : Dataset,
) -> YoloManifest raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidInput("YOLO manifest is not valid JSON")
  }
  let raw : YoloManifestJson = @json.from_json(json) catch {
    _ =>
      raise InvalidInput(
        "YOLO manifest needs category_ids and images with valid field types",
      )
  }
  if raw.category_ids.is_empty() {
    raise InvalidInput("YOLO manifest category_ids must be nonempty")
  }
  let known_images : Map[Int, Bool] = Map([])
  let known_categories : Map[Int, Bool] = Map([])
  for image in dataset.images {
    known_images[image.id] = true
  }
  for category in dataset.categories {
    known_categories[category.id] = true
  }
  for index, category_id in raw.category_ids {
    if !known_categories.contains(category_id) {
      raise InvalidInput(
        "YOLO manifest category_ids[\{index}] \{category_id} is not in the dataset",
      )
    }
  }
  let seen_images : Map[Int, Bool] = Map([])
  let seen_files : Map[String, Bool] = Map([])
  let images : Array[YoloFile] = []
  for index, entry in raw.images {
    let file : YoloFileJson = @json.from_json(entry) catch {
      _ =>
        raise InvalidInput("YOLO manifest images[\{index}] has invalid fields")
    }
    if !known_images.contains(file.image_id) {
      raise InvalidInput(
        "YOLO manifest images[\{index}].image_id \{file.image_id} is not in the dataset",
      )
    }
    if seen_images.contains(file.image_id) {
      raise InvalidInput(
        "YOLO manifest images[\{index}].image_id \{file.image_id} is duplicated",
      )
    }
    if !valid_yolo_file_path(file.file) {
      raise InvalidInput(
        "YOLO manifest images[\{index}].file must be a relative path without . or .. segments, backslashes, or a drive prefix",
      )
    }
    if seen_files.contains(file.file) {
      raise InvalidInput(
        "YOLO manifest images[\{index}].file \{file.file} is duplicated",
      )
    }
    seen_images[file.image_id] = true
    seen_files[file.file] = true
    images.push({ image_id: file.image_id, file: file.file, })
  }
  { category_ids: raw.category_ids.copy(), images, }
}
