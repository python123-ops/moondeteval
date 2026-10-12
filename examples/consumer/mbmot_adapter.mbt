///|
/// Convert one MBMOT detector frame to MoonDetEval detections.
/// The caller supplies the COCO image ID and must ensure generated IDs are
/// unique across all frames in the evaluation dataset.
pub fn adapt_mbmot_frame(
  image_id : Int32,
  first_detection_id : Int32,
  detections : Array[@mbmot.Detection],
) -> Array[@moondeteval.Detection] raise @moondeteval.EvalError {
  let result : Array[@moondeteval.Detection] = []
  for index, detection in detections {
    let id = first_detection_id.to_int64() + index.to_int64()
    if id > 2147483647L {
      raise @moondeteval.InvalidInput("MBMOT detection ID exceeds Int range")
    }
    let (x, y, width, height) = detection.bbox().to_xywh()
    let box = @moondeteval.Box::from_xywh(x, y, width, height)
    result.push(
      @moondeteval.Detection::new(
        id.to_int(),
        image_id,
        detection.class_id(),
        box,
        detection.score(),
      ),
    )
  }
  result
}

///|
/// Convert ordered detector frames into one evaluation input. Each frame uses
/// one distinct target image ID. `class_map` maps MBMOT class IDs to dataset
/// category IDs; track IDs are not part of detector evaluation.
pub fn adapt_mbmot_frames(
  frames : Array[(Int32, Array[@mbmot.Detection])],
  class_map : Array[(Int32, Int32)],
  first_detection_id : Int32,
) -> Array[@moondeteval.Detection] raise @moondeteval.EvalError {
  for index, (source, _) in class_map {
    for previous in 0..<index {
      if class_map[previous].0 == source {
        raise @moondeteval.InvalidInput("duplicate MBMOT class mapping")
      }
    }
  }
  let seen_images : Array[Int32] = []
  let result : Array[@moondeteval.Detection] = []
  for (image_id, detections) in frames {
    if seen_images.contains(image_id) {
      raise @moondeteval.InvalidInput("duplicate MBMOT frame image ID")
    }
    seen_images.push(image_id)
    for detection in detections {
      let mut category_id : Int32? = None
      for (source, target) in class_map {
        if source == detection.class_id() {
          category_id = Some(target)
          break
        }
      }
      let target_id = match category_id {
        Some(id) => id
        None => raise @moondeteval.InvalidInput("unmapped MBMOT class ID")
      }
      let id = first_detection_id.to_int64() + result.length().to_int64()
      if id > 2147483647L {
        raise @moondeteval.InvalidInput("MBMOT detection ID exceeds Int range")
      }
      let (x, y, width, height) = detection.bbox().to_xywh()
      let box = @moondeteval.Box::from_xywh(x, y, width, height)
      result.push(
        @moondeteval.Detection::new(
          id.to_int(),
          image_id,
          target_id,
          box,
          detection.score(),
        ),
      )
    }
  }
  result
}
