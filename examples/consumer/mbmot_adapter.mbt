///|
/// Convert one MBMOT detector frame to MoonDetEval detections.
/// The caller supplies the COCO image ID and must ensure generated IDs are
/// unique across all frames in the evaluation dataset.
pub fn adapt_mbmot_frame(
  image_id : Int,
  first_detection_id : Int,
  detections : Array[@mbmot.Detection],
) -> Array[@moondeteval.Detection] raise @moondeteval.EvalError {
  let result : Array[@moondeteval.Detection] = []
  for index, detection in detections {
    let (x, y, width, height) = detection.bbox().to_xywh()
    let box = @moondeteval.Box::from_xywh(x, y, width, height)
    result.push(
      @moondeteval.Detection::new(
        first_detection_id + index,
        image_id,
        detection.class_id(),
        box,
        detection.score(),
      ),
    )
  }
  result
}
