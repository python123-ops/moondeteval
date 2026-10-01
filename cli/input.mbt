///|
/// Read one UTF-8 input with both per-file and remaining-total byte limits.
async fn read_limited_input(
  path : String,
  max_input_bytes : Int,
  remaining_bytes : Int64,
) -> (String, Int64) raise @moondeteval.EvalError {
  let size = @fs.file_size(path) catch {
    error =>
      raise @moondeteval.InvalidInput(
        "cannot inspect input " + path + ": \{error}",
      )
  }
  if size > max_input_bytes.to_int64() {
    raise @moondeteval.InvalidInput(
      "input " +
      path +
      " is \{size} bytes, exceeding --max-input-bytes \{max_input_bytes}",
    )
  }
  if size > remaining_bytes {
    raise @moondeteval.InvalidInput(
      "input " + path + " exceeds --max-total-input-bytes",
    )
  }
  let data = @fs.read_file(path) catch {
    error =>
      raise @moondeteval.InvalidInput(
        "cannot read input " + path + ": \{error}",
      )
  }
  let actual = data.binary().length().to_int64()
  if actual > max_input_bytes.to_int64() {
    raise @moondeteval.InvalidInput(
      "input " + path + " grew beyond --max-input-bytes during read",
    )
  }
  if actual > remaining_bytes {
    raise @moondeteval.InvalidInput(
      "input " + path + " grew beyond --max-total-input-bytes during read",
    )
  }
  let content = data.text() catch {
    _ =>
      raise @moondeteval.InvalidInput("input " + path + " is not valid UTF-8")
  }
  (content, actual)
}

///|
/// A manifest file uses slash-separated relative paths on every platform.
/// Keep its own platform separator when joining a validated relative file.
fn manifest_parent(path : String) -> String {
  let current = StringBuilder()
  let mut parent = "./"
  for character in path.iter() {
    current.write_char(character)
    if character == '/' || character == '\\' {
      parent = current.to_string()
    }
  }
  parent
}

///|
/// The top-level source has already been read and counted by the caller.
/// Return detections plus bytes read from any manifest-listed TXT files.
async fn load_predictions(
  source : String,
  path : String,
  format : String,
  dataset : @moondeteval.Dataset,
  max_input_bytes : Int,
  remaining_bytes : Int64,
  max_records : Int,
) -> (Array[@moondeteval.Detection], Int64) raise @moondeteval.EvalError {
  if format == "coco" {
    let detections = @moondeteval.parse_coco_detections(source) catch {
      error =>
        raise @moondeteval.InvalidInput(
          "detections " + path + ": " + error.message(),
        )
    }
    return (detections, 0L)
  }
  let manifest = @moondeteval.parse_yolo_manifest(source, dataset) catch {
    error =>
      raise @moondeteval.InvalidInput(
        "YOLO manifest " + path + ": " + error.message(),
      )
  }
  if manifest.images().length() > max_records ||
    manifest.category_ids().length() > max_records {
    raise @moondeteval.InvalidInput(
      "YOLO manifest exceeds --max-records \{max_records}",
    )
  }
  let parent = manifest_parent(path)
  let detections : Array[@moondeteval.Detection] = []
  let mut used = 0L
  for entry in manifest.images() {
    let txt_path = parent + entry.file()
    let (txt, size) = read_limited_input(
      txt_path,
      max_input_bytes,
      remaining_bytes - used,
    )
    used += size
    let parsed = @moondeteval.parse_yolo_detections(
      txt,
      dataset,
      entry.image_id(),
      manifest.category_ids(),
      first_detection_id=detections.length(),
    ) catch {
      error =>
        raise @moondeteval.InvalidInput(
          "YOLO file " + txt_path + ": " + error.message(),
        )
    }
    if parsed.length() > max_records - detections.length() {
      raise @moondeteval.InvalidInput(
        "YOLO predictions exceed --max-records \{max_records}",
      )
    }
    for detection in parsed {
      detections.push(detection)
    }
  }
  (detections, used)
}
