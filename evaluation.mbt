///|
/// One COCO-style summary value. -1 means there are no eligible ground truths.
pub struct Metrics {
  ap : Double
  ap50 : Double
  ap75 : Double
  ap_small : Double
  ap_medium : Double
  ap_large : Double
  ar1 : Double
  ar10 : Double
  ar100 : Double
  ar_small : Double
  ar_medium : Double
  ar_large : Double
} derive(Debug, ToJson)

///|
pub extend Metrics with Debug::{to_repr}

///|
pub extend Metrics with ToJson::{to_json}

///|
pub fn Metrics::ap(self : Metrics) -> Double {
  self.ap
}

///|
pub fn Metrics::ap50(self : Metrics) -> Double {
  self.ap50
}

///|
pub fn Metrics::ap75(self : Metrics) -> Double {
  self.ap75
}

///|
pub fn Metrics::ap_small(self : Metrics) -> Double {
  self.ap_small
}

///|
pub fn Metrics::ap_medium(self : Metrics) -> Double {
  self.ap_medium
}

///|
pub fn Metrics::ap_large(self : Metrics) -> Double {
  self.ap_large
}

///|
pub fn Metrics::ar1(self : Metrics) -> Double {
  self.ar1
}

///|
pub fn Metrics::ar10(self : Metrics) -> Double {
  self.ar10
}

///|
pub fn Metrics::ar100(self : Metrics) -> Double {
  self.ar100
}

///|
pub fn Metrics::ar_small(self : Metrics) -> Double {
  self.ar_small
}

///|
pub fn Metrics::ar_medium(self : Metrics) -> Double {
  self.ar_medium
}

///|
pub fn Metrics::ar_large(self : Metrics) -> Double {
  self.ar_large
}

///|
pub struct ClassMetrics {
  category_id : Int
  metrics : Metrics
} derive(ToJson)

///|
pub extend ClassMetrics with ToJson::{to_json}

///|
pub fn ClassMetrics::category_id(self : ClassMetrics) -> Int {
  self.category_id
}

///|
pub fn ClassMetrics::metrics(self : ClassMetrics) -> Metrics {
  self.metrics
}

///|
pub struct EvaluationReport {
  schema_version : String
  evaluator_version : String
  config : EvalConfig
  counts : InputCounts
  summary : Metrics
  classes : Array[ClassMetrics]
  diagnostics : Array[MatchDiagnostic]
  quality_warnings : Array[QualityWarning]
} derive(ToJson)

///|
/// Input sizes and detections retained by the all-area maxDets=100 evaluation.
pub struct InputCounts {
  images : Int
  categories : Int
  ground_truths : Int
  detections : Int
  evaluated_detections : Int
} derive(ToJson)

///|
pub extend InputCounts with ToJson::{to_json}

///|
pub fn InputCounts::images(self : InputCounts) -> Int {
  self.images
}

///|
pub fn InputCounts::categories(self : InputCounts) -> Int {
  self.categories
}

///|
pub fn InputCounts::ground_truths(self : InputCounts) -> Int {
  self.ground_truths
}

///|
pub fn InputCounts::detections(self : InputCounts) -> Int {
  self.detections
}

///|
pub fn InputCounts::evaluated_detections(self : InputCounts) -> Int {
  self.evaluated_detections
}

///|
/// A nonfatal spatial input warning; scoring uses the original box unchanged.
pub struct QualityWarning {
  source : String
  record_id : Int
  image_id : Int
  category_id : Int
  kind : String
} derive(ToJson)

///|
pub extend QualityWarning with ToJson::{to_json}

///|
pub fn QualityWarning::source(self : QualityWarning) -> String {
  self.source
}

///|
pub fn QualityWarning::record_id(self : QualityWarning) -> Int {
  self.record_id
}

///|
pub fn QualityWarning::image_id(self : QualityWarning) -> Int {
  self.image_id
}

///|
pub fn QualityWarning::category_id(self : QualityWarning) -> Int {
  self.category_id
}

///|
pub fn QualityWarning::kind(self : QualityWarning) -> String {
  self.kind
}

///|
pub extend EvaluationReport with ToJson::{to_json}

///|
pub fn EvaluationReport::to_json_string(self : EvaluationReport) -> String {
  @json.to_json(self).stringify()
}

///|
pub fn EvaluationReport::summary(self : EvaluationReport) -> Metrics {
  self.summary
}

///|
pub fn EvaluationReport::config(self : EvaluationReport) -> EvalConfig {
  self.config
}

///|
pub fn EvaluationReport::counts(self : EvaluationReport) -> InputCounts {
  self.counts
}

///|
pub fn EvaluationReport::evaluator_version(self : EvaluationReport) -> String {
  self.evaluator_version
}

///|
pub fn EvaluationReport::quality_warnings(
  self : EvaluationReport,
) -> Array[QualityWarning] {
  self.quality_warnings.copy()
}

///|
pub fn EvaluationReport::classes(
  self : EvaluationReport,
) -> Array[ClassMetrics] {
  self.classes.copy()
}

///|
/// One detection decision, or one unmatched eligible ground truth, at an IoU threshold.
/// Diagnostics use the all-area range and maxDets=100.
pub struct MatchDiagnostic {
  iou_threshold : Double
  image_id : Int
  category_id : Int
  detection_id : Int?
  ground_truth_id : Int?
  iou : Double
  status : String
  reason : String
} derive(ToJson)

///|
pub extend MatchDiagnostic with ToJson::{to_json}

///|
pub fn MatchDiagnostic::iou_threshold(self : MatchDiagnostic) -> Double {
  self.iou_threshold
}

///|
pub fn MatchDiagnostic::image_id(self : MatchDiagnostic) -> Int {
  self.image_id
}

///|
pub fn MatchDiagnostic::category_id(self : MatchDiagnostic) -> Int {
  self.category_id
}

///|
pub fn MatchDiagnostic::detection_id(self : MatchDiagnostic) -> Int? {
  self.detection_id
}

///|
pub fn MatchDiagnostic::ground_truth_id(self : MatchDiagnostic) -> Int? {
  self.ground_truth_id
}

///|
/// IoU of the chosen match, or zero when no ground truth was matched.
pub fn MatchDiagnostic::iou(self : MatchDiagnostic) -> Double {
  self.iou
}

///|
pub fn MatchDiagnostic::status(self : MatchDiagnostic) -> String {
  self.status
}

///|
pub fn MatchDiagnostic::reason(self : MatchDiagnostic) -> String {
  self.reason
}

///|
pub fn EvaluationReport::diagnostics(
  self : EvaluationReport,
) -> Array[MatchDiagnostic] {
  self.diagnostics.copy()
}

///|
/// AP and AR average over these IoU thresholds. AP50 and AP75 remain fixed probes.
pub struct EvalConfig {
  iou_thresholds : Array[Double]
  include_diagnostics : Bool
  ignore_policy : String
} derive(ToJson)

///|
pub extend EvalConfig with ToJson::{to_json}

///|
pub fn EvalConfig::new(
  iou_thresholds : Array[Double],
  include_diagnostics? : Bool = false,
  ignore_policy? : String = "coco_bbox",
) -> EvalConfig raise EvalError {
  if iou_thresholds.is_empty() || iou_thresholds.length() > 100 {
    raise InvalidConfig("IoU thresholds must contain 1 to 100 values")
  }
  let mut previous = 0.0
  for threshold in iou_thresholds {
    if !finite(threshold) || threshold <= previous || threshold > 1.0 {
      raise InvalidConfig(
        "IoU thresholds must be finite, strictly increasing, and in (0,1]",
      )
    }
    previous = threshold
  }
  if ignore_policy != "coco_bbox" && ignore_policy != "respect_explicit" {
    raise InvalidConfig("ignore_policy must be coco_bbox or respect_explicit")
  }
  { iou_thresholds: iou_thresholds.copy(), include_diagnostics, ignore_policy, }
}

///|
pub fn EvalConfig::coco() -> EvalConfig {
  {
    iou_thresholds: [
      0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.8999999999999999, 0.95,
    ],
    include_diagnostics: false,
    ignore_policy: "coco_bbox",
  }
}

///|
pub fn EvalConfig::iou_thresholds(self : EvalConfig) -> Array[Double] {
  self.iou_thresholds.copy()
}

///|
pub fn EvalConfig::include_diagnostics(self : EvalConfig) -> Bool {
  self.include_diagnostics
}

///|
pub fn EvalConfig::ignore_policy(self : EvalConfig) -> String {
  self.ignore_policy
}

///|
priv struct RankedDetection {
  detection : Detection
  order : Int
}

///|
priv struct RankedTruth {
  truth : GroundTruth
  order : Int
}

///|
priv struct MatchRecord {
  score : Double
  order : Int
  matched : Bool
  ignored : Bool
}

///|
priv struct CurveValue {
  ap : Double
  ar : Double
}

///|
fn overlap(detection : Box, truth : Box, crowd : Bool) -> Double {
  if !crowd {
    return detection.iou(truth)
  }
  let width = (detection.x2.min(truth.x2) - detection.x1.max(truth.x1)).max(0.0)
  let height = (detection.y2.min(truth.y2) - detection.y1.max(truth.y1)).max(
    0.0,
  )
  width * height / detection.area()
}

///|
fn in_area(area : Double, lower : Double, upper : Double) -> Bool {
  area >= lower && area <= upper
}

///|
fn truth_ignored(
  truth : GroundTruth,
  lower : Double,
  upper : Double,
  respect_explicit_ignore : Bool,
) -> Bool {
  truth.iscrowd ||
  (respect_explicit_ignore && truth.ignore) ||
  !in_area(truth.area, lower, upper)
}

///|
fn ranked_before(left : RankedDetection, right : RankedDetection) -> Int {
  if left.detection.score > right.detection.score {
    -1
  } else if left.detection.score < right.detection.score {
    1
  } else {
    left.order - right.order
  }
}

///|
fn record_before(left : MatchRecord, right : MatchRecord) -> Int {
  if left.score > right.score {
    -1
  } else if left.score < right.score {
    1
  } else {
    left.order - right.order
  }
}

///|
/// A read-only explanation of an unmatched, non-ignored detection.
fn classify_false_positive(
  dataset : Dataset,
  image_id : Int,
  category_id : Int,
  detection : Box,
  truths : Array[RankedTruth],
  used : Array[Bool],
  ignored : Array[Bool],
  threshold : Double,
  respect_explicit_ignore : Bool,
) -> String {
  for index in 0..<truths.length() {
    let truth = truths[index].truth
    if used[index] &&
      !ignored[index] &&
      overlap(detection, truth.bbox, false) >= threshold {
      return "duplicate"
    }
  }
  for truth in dataset.truths {
    if truth.image_id == image_id &&
      truth.category_id != category_id &&
      !truth.iscrowd &&
      (!respect_explicit_ignore || !truth.ignore) &&
      overlap(detection, truth.bbox, false) >= threshold {
      return "wrong_class"
    }
  }
  for index in 0..<truths.length() {
    let truth = truths[index].truth
    if !ignored[index] && overlap(detection, truth.bbox, false) >= 0.1 {
      return "localization"
    }
  }
  "background"
}

///|
fn evaluate_curve(
  dataset : Dataset,
  detections : Array[RankedDetection],
  category_id : Int,
  threshold : Double,
  lower : Double,
  upper : Double,
  max_dets : Int,
  trace : Array[MatchDiagnostic]?,
  respect_explicit_ignore : Bool,
) -> CurveValue {
  let records : Array[MatchRecord] = []
  let mut positives = 0
  let images = dataset.images.copy()
  images.sort_by(fn(left, right) {
    if left.id < right.id {
      -1
    } else if left.id > right.id {
      1
    } else {
      0
    }
  })
  for image in images {
    let truths : Array[RankedTruth] = []
    let candidates : Array[RankedDetection] = []
    for order, truth in dataset.truths {
      if truth.image_id == image.id && truth.category_id == category_id {
        truths.push({ truth, order, })
      }
    }
    for candidate in detections {
      if candidate.detection.image_id == image.id &&
        candidate.detection.category_id == category_id {
        candidates.push(candidate)
      }
    }
    truths.sort_by(fn(left, right) {
      let left_ignored = truth_ignored(
        left.truth,
        lower,
        upper,
        respect_explicit_ignore,
      )
      let right_ignored = truth_ignored(
        right.truth,
        lower,
        upper,
        respect_explicit_ignore,
      )
      if left_ignored == right_ignored {
        left.order - right.order
      } else if left_ignored {
        1
      } else {
        -1
      }
    })
    candidates.sort_by(ranked_before)
    let used = Array::make(truths.length(), false)
    let ignored = Array::makei(truths.length(), fn(index) {
      truth_ignored(truths[index].truth, lower, upper, respect_explicit_ignore)
    })
    for flag in ignored {
      if !flag {
        positives += 1
      }
    }
    let count = candidates.length().min(max_dets)
    for detection_index in 0..<count {
      let candidate = candidates[detection_index]
      let mut best = -1
      let mut best_overlap = threshold.min(1.0 - 1.0e-10)
      for truth_index in 0..<truths.length() {
        let truth = truths[truth_index].truth
        if used[truth_index] && !truth.iscrowd {
          continue
        }
        if best >= 0 && !ignored[best] && ignored[truth_index] {
          break
        }
        let current = overlap(
          candidate.detection.bbox,
          truth.bbox,
          truth.iscrowd,
        )
        if current < best_overlap {
          continue
        }
        best_overlap = current
        best = truth_index
      }
      let match_ignored = if best >= 0 {
        ignored[best]
      } else {
        !in_area(candidate.detection.bbox.area(), lower, upper)
      }
      if best >= 0 {
        used[best] = true
      }
      match trace {
        Some(entries) => {
          let ground_truth_id = if best >= 0 {
            Some(truths[best].truth.id)
          } else {
            None
          }
          let reason = if best >= 0 {
            let truth = truths[best].truth
            if truth.iscrowd {
              "crowd"
            } else if respect_explicit_ignore && truth.ignore {
              "ground_truth_ignore"
            } else if !in_area(truth.area, lower, upper) {
              "ground_truth_area"
            } else {
              "matched"
            }
          } else if match_ignored {
            "detection_area"
          } else {
            classify_false_positive(
              dataset,
              image.id,
              category_id,
              candidate.detection.bbox,
              truths,
              used,
              ignored,
              threshold,
              respect_explicit_ignore,
            )
          }
          entries.push({
            iou_threshold: threshold,
            image_id: image.id,
            category_id,
            detection_id: Some(candidate.detection.id),
            ground_truth_id,
            iou: if best >= 0 {
              best_overlap
            } else {
              0.0
            },
            status: if match_ignored {
              "ignored"
            } else if best >= 0 {
              "tp"
            } else {
              "fp"
            },
            reason,
          })
        }
        None => ()
      }
      records.push({
        score: candidate.detection.score,
        order: records.length(),
        matched: best >= 0,
        ignored: match_ignored,
      })
    }
    match trace {
      Some(entries) =>
        for truth_index in 0..<truths.length() {
          if !ignored[truth_index] && !used[truth_index] {
            entries.push({
              iou_threshold: threshold,
              image_id: image.id,
              category_id,
              detection_id: None,
              ground_truth_id: Some(truths[truth_index].truth.id),
              iou: 0.0,
              status: "fn",
              reason: "unmatched_ground_truth",
            })
          }
        }
      None => ()
    }
  }
  if positives == 0 {
    return { ap: -1.0, ar: -1.0, }
  }
  records.sort_by(record_before)
  let mut tp = 0
  let mut fp = 0
  let precision : Array[Double] = []
  let recall : Array[Double] = []
  for record in records {
    if record.ignored {
      continue
    }
    if record.matched {
      tp += 1
    } else {
      fp += 1
    }
    precision.push(tp.to_double() / (tp + fp).to_double())
    recall.push(tp.to_double() / positives.to_double())
  }
  let ar = tp.to_double() / positives.to_double()
  for index = precision.length() - 2; index >= 0; index = index - 1 {
    if precision[index] < precision[index + 1] {
      precision[index] = precision[index + 1]
    }
  }
  let mut ap = 0.0
  let mut index = 0
  for sample in 0..<=100 {
    let target = sample.to_double() / 100.0
    while index < recall.length() && recall[index] < target {
      index += 1
    }
    if index < precision.length() {
      ap += precision[index]
    }
  }
  { ap: ap / 101.0, ar, }
}

///|
fn average(values : Array[Double]) -> Double {
  let mut sum = 0.0
  let mut count = 0
  for value in values {
    if value >= 0.0 {
      sum += value
      count += 1
    }
  }
  if count == 0 {
    -1.0
  } else {
    sum / count.to_double()
  }
}

///|
fn metrics_for_category(
  dataset : Dataset,
  detections : Array[RankedDetection],
  category_id : Int,
  thresholds : Array[Double],
  diagnostics : Array[MatchDiagnostic]?,
  respect_explicit_ignore : Bool,
) -> Metrics {
  let all_ap : Array[Double] = []
  let all_ar1 : Array[Double] = []
  let all_ar10 : Array[Double] = []
  let all_ar100 : Array[Double] = []
  let small_ap : Array[Double] = []
  let medium_ap : Array[Double] = []
  let large_ap : Array[Double] = []
  let small_ar : Array[Double] = []
  let medium_ar : Array[Double] = []
  let large_ar : Array[Double] = []
  let mut ap50 = -1.0
  let mut ap75 = -1.0
  let mut saw_ap50 = false
  let mut saw_ap75 = false
  for threshold in thresholds {
    let all = evaluate_curve(
      dataset, detections, category_id, threshold, 0.0, 1.0e10, 100, diagnostics,
      respect_explicit_ignore,
    )
    all_ap.push(all.ap)
    all_ar100.push(all.ar)
    all_ar1.push(
      evaluate_curve(
        dataset,
        detections,
        category_id,
        threshold,
        0.0,
        1.0e10,
        1,
        None,
        respect_explicit_ignore,
      ).ar,
    )
    all_ar10.push(
      evaluate_curve(
        dataset,
        detections,
        category_id,
        threshold,
        0.0,
        1.0e10,
        10,
        None,
        respect_explicit_ignore,
      ).ar,
    )
    let small = evaluate_curve(
      dataset,
      detections,
      category_id,
      threshold,
      0.0,
      1024.0,
      100,
      None,
      respect_explicit_ignore,
    )
    let medium = evaluate_curve(
      dataset,
      detections,
      category_id,
      threshold,
      1024.0,
      9216.0,
      100,
      None,
      respect_explicit_ignore,
    )
    let large = evaluate_curve(
      dataset,
      detections,
      category_id,
      threshold,
      9216.0,
      1.0e10,
      100,
      None,
      respect_explicit_ignore,
    )
    small_ap.push(small.ap)
    medium_ap.push(medium.ap)
    large_ap.push(large.ap)
    small_ar.push(small.ar)
    medium_ar.push(medium.ar)
    large_ar.push(large.ar)
    if threshold == 0.5 {
      ap50 = all.ap
      saw_ap50 = true
    }
    if threshold == 0.75 {
      ap75 = all.ap
      saw_ap75 = true
    }
  }
  if !saw_ap50 {
    ap50 = evaluate_curve(
        dataset,
        detections,
        category_id,
        0.5,
        0.0,
        1.0e10,
        100,
        None,
        respect_explicit_ignore,
      ).ap
  }
  if !saw_ap75 {
    ap75 = evaluate_curve(
        dataset,
        detections,
        category_id,
        0.75,
        0.0,
        1.0e10,
        100,
        None,
        respect_explicit_ignore,
      ).ap
  }
  {
    ap: average(all_ap),
    ap50,
    ap75,
    ap_small: average(small_ap),
    ap_medium: average(medium_ap),
    ap_large: average(large_ap),
    ar1: average(all_ar1),
    ar10: average(all_ar10),
    ar100: average(all_ar100),
    ar_small: average(small_ar),
    ar_medium: average(medium_ar),
    ar_large: average(large_ar),
  }
}

///|
/// Evaluate continuous-coordinate bounding boxes with default COCO thresholds.
pub fn evaluate(
  dataset : Dataset,
  predictions : Array[Detection],
) -> EvaluationReport raise EvalError {
  evaluate_internal(dataset, predictions, EvalConfig::coco())
}

///|
/// Evaluate and retain per-detection decisions for the default IoU thresholds.
pub fn evaluate_with_diagnostics(
  dataset : Dataset,
  predictions : Array[Detection],
) -> EvaluationReport raise EvalError {
  let default = EvalConfig::coco()
  evaluate_internal(dataset, predictions, {
    iou_thresholds: default.iou_thresholds,
    include_diagnostics: true,
    ignore_policy: default.ignore_policy,
  })
}

///|
/// Evaluate with custom AP/AR IoU thresholds. Area bins and maxDets remain COCO defaults.
pub fn evaluate_with_config(
  dataset : Dataset,
  predictions : Array[Detection],
  config : EvalConfig,
) -> EvaluationReport raise EvalError {
  evaluate_internal(dataset, predictions, config)
}

///|
fn evaluate_internal(
  dataset : Dataset,
  predictions : Array[Detection],
  config : EvalConfig,
) -> EvaluationReport raise EvalError {
  let image_ids : Map[Int, Bool] = Map([])
  let images_by_id : Map[Int, Image] = Map([])
  let category_ids : Map[Int, Bool] = Map([])
  let detection_ids : Map[Int, Bool] = Map([])
  for image in dataset.images {
    image_ids[image.id] = true
    images_by_id[image.id] = image
  }
  for category in dataset.categories {
    category_ids[category.id] = true
  }
  let detections : Array[RankedDetection] = []
  let quality_warnings : Array[QualityWarning] = []
  let per_image_category : Map[String, Int] = Map([])
  let mut evaluated_detections = 0
  for truth in dataset.truths {
    match images_by_id.get(truth.image_id) {
      Some(image) =>
        if box_outside_image(truth.bbox, image) {
          quality_warnings.push({
            source: "ground_truth",
            record_id: truth.id,
            image_id: truth.image_id,
            category_id: truth.category_id,
            kind: "outside_image",
          })
        }
      None => ()
    }
  }
  for index, prediction in predictions {
    if detection_ids.contains(prediction.id) {
      raise InvalidInput("duplicate detection id \{prediction.id}")
    }
    if !image_ids.contains(prediction.image_id) ||
      !category_ids.contains(prediction.category_id) {
      raise InvalidInput(
        "detection \{prediction.id} references unknown image or category",
      )
    }
    detection_ids[prediction.id] = true
    detections.push({ detection: prediction, order: index, })
    let group = "\{prediction.image_id}:\{prediction.category_id}"
    let count = match per_image_category.get(group) {
      Some(value) => value
      None => 0
    }
    per_image_category[group] = count + 1
    if count < 100 {
      evaluated_detections += 1
    }
    match images_by_id.get(prediction.image_id) {
      Some(image) =>
        if box_outside_image(prediction.bbox, image) {
          quality_warnings.push({
            source: "detection",
            record_id: prediction.id,
            image_id: prediction.image_id,
            category_id: prediction.category_id,
            kind: "outside_image",
          })
        }
      None => ()
    }
  }
  let classes : Array[ClassMetrics] = []
  let diagnostics : Array[MatchDiagnostic] = []
  let ap : Array[Double] = []
  let ap50 : Array[Double] = []
  let ap75 : Array[Double] = []
  let ap_small : Array[Double] = []
  let ap_medium : Array[Double] = []
  let ap_large : Array[Double] = []
  let ar1 : Array[Double] = []
  let ar10 : Array[Double] = []
  let ar100 : Array[Double] = []
  let ar_small : Array[Double] = []
  let ar_medium : Array[Double] = []
  let ar_large : Array[Double] = []
  for category in dataset.categories {
    let metrics = metrics_for_category(
      dataset,
      detections,
      category.id,
      config.iou_thresholds,
      if config.include_diagnostics {
        Some(diagnostics)
      } else {
        None
      },
      config.ignore_policy == "respect_explicit",
    )
    classes.push({ category_id: category.id, metrics, })
    ap.push(metrics.ap)
    ap50.push(metrics.ap50)
    ap75.push(metrics.ap75)
    ap_small.push(metrics.ap_small)
    ap_medium.push(metrics.ap_medium)
    ap_large.push(metrics.ap_large)
    ar1.push(metrics.ar1)
    ar10.push(metrics.ar10)
    ar100.push(metrics.ar100)
    ar_small.push(metrics.ar_small)
    ar_medium.push(metrics.ar_medium)
    ar_large.push(metrics.ar_large)
  }
  {
    schema_version: "0.1.0",
    evaluator_version: "0.1.0",
    config,
    counts: {
      images: dataset.images.length(),
      categories: dataset.categories.length(),
      ground_truths: dataset.truths.length(),
      detections: predictions.length(),
      evaluated_detections,
    },
    summary: {
      ap: average(ap),
      ap50: average(ap50),
      ap75: average(ap75),
      ap_small: average(ap_small),
      ap_medium: average(ap_medium),
      ap_large: average(ap_large),
      ar1: average(ar1),
      ar10: average(ar10),
      ar100: average(ar100),
      ar_small: average(ar_small),
      ar_medium: average(ar_medium),
      ar_large: average(ar_large),
    },
    classes,
    diagnostics,
    quality_warnings,
  }
}

///|
fn box_outside_image(box : Box, image : Image) -> Bool {
  box.x1 < 0.0 ||
  box.y1 < 0.0 ||
  box.x2 > image.width.to_double() ||
  box.y2 > image.height.to_double()
}
