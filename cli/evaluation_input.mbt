///|
priv enum EvaluationInput {
  Bbox(
    @moondeteval.Dataset,
    Array[@moondeteval.Detection],
    Array[@moondeteval.Detection]?
  )
  Segm(
    @moondeteval.MaskDataset,
    Array[@moondeteval.MaskDetection],
    Array[@moondeteval.MaskDetection]?
  )
}

///|
priv enum CliResult {
  Single(@moondeteval.EvaluationReport)
  Paired(@moondeteval.ComparisonReport)
}

///|
fn EvaluationInput::sizes(
  self : EvaluationInput,
) -> (Int32, Int32, Int32, Int32) {
  match self {
    Bbox(dataset, predictions, other) =>
      (
        dataset.images().length() + dataset.categories().length(),
        dataset.truths().length(),
        predictions.length(),
        match other {
          Some(items) => items.length() + dataset.truths().length()
          None => 0
        },
      )
    Segm(dataset, predictions, other) =>
      (
        dataset.images().length() + dataset.categories().length(),
        dataset.truths().length(),
        predictions.length(),
        match other {
          Some(items) => items.length() + dataset.truths().length()
          None => 0
        },
      )
  }
}

///|
fn EvaluationInput::evaluate(
  self : EvaluationInput,
  config : @moondeteval.EvalConfig,
  max_iou_cache_pairs : Int32,
) -> CliResult raise @moondeteval.EvalError {
  match self {
    Bbox(dataset, predictions, Some(other)) =>
      Paired(
        @moondeteval.compare_predictions_with_config(
          dataset, predictions, other, config,
        ),
      )
    Bbox(dataset, predictions, None) =>
      Single(@moondeteval.evaluate_with_config(dataset, predictions, config))
    Segm(dataset, predictions, Some(other)) =>
      Paired(
        @moondeteval.compare_mask_predictions_with_config(
          dataset,
          predictions,
          other,
          config,
          max_iou_cache_pairs~,
        ),
      )
    Segm(dataset, predictions, None) =>
      Single(
        @moondeteval.evaluate_masks_with_config(
          dataset,
          predictions,
          config,
          max_iou_cache_pairs~,
        ),
      )
  }
}

///|
async fn load_evaluation_input(
  sources : Array[String],
  paths : Array[String],
  iou_type : String,
  prediction_format : String,
  comparison_format : String,
  max_input_bytes : Int32,
  remaining_bytes : Int64,
  max_records : Int32,
) -> (EvaluationInput, Int64) raise @moondeteval.EvalError {
  if iou_type == "segm" {
    let dataset = @moondeteval.parse_coco_mask_dataset(sources[0]) catch {
      error =>
        raise @moondeteval.InvalidInput(
          "ground truth " + paths[0] + ": " + error.message(),
        )
    }
    let predictions = @moondeteval.parse_coco_mask_detections_with_dataset(
      sources[1],
      dataset,
    ) catch {
      error =>
        raise @moondeteval.InvalidInput(
          "detections " + paths[1] + ": " + error.message(),
        )
    }
    let other = if sources.length() == 3 {
      Some(
        @moondeteval.parse_coco_mask_detections_with_dataset(
          sources[2],
          dataset,
        ) catch {
          error =>
            raise @moondeteval.InvalidInput(
              "detections " + paths[2] + ": " + error.message(),
            )
        },
      )
    } else {
      None
    }
    return (Segm(dataset, predictions, other), 0L)
  }
  let dataset = @moondeteval.parse_coco_dataset(sources[0]) catch {
    error =>
      raise @moondeteval.InvalidInput(
        "ground truth " + paths[0] + ": " + error.message(),
      )
  }
  let (predictions, used) = load_predictions(
    sources[1],
    paths[1],
    prediction_format,
    dataset,
    max_input_bytes,
    remaining_bytes,
    max_records,
  )
  let (other, extra) = if sources.length() == 3 {
    let (parsed, extra) = load_predictions(
      sources[2],
      paths[2],
      comparison_format,
      dataset,
      max_input_bytes,
      remaining_bytes - used,
      max_records,
    )
    (Some(parsed), extra)
  } else {
    (None, 0L)
  }
  (Bbox(dataset, predictions, other), used + extra)
}
