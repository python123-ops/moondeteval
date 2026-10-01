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
  summary : Metrics
  classes : Array[ClassMetrics]
} derive(ToJson)

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
pub fn EvaluationReport::classes(
  self : EvaluationReport,
) -> Array[ClassMetrics] {
  self.classes.copy()
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
fn evaluate_curve(
  dataset : Dataset,
  detections : Array[RankedDetection],
  category_id : Int,
  threshold : Double,
  lower : Double,
  upper : Double,
  max_dets : Int,
) -> CurveValue {
  let records : Array[MatchRecord] = []
  let mut positives = 0
  for image in dataset.images {
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
      let left_ignored = left.truth.ignore ||
        left.truth.iscrowd ||
        !in_area(left.truth.area, lower, upper)
      let right_ignored = right.truth.ignore ||
        right.truth.iscrowd ||
        !in_area(right.truth.area, lower, upper)
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
      truths[index].truth.ignore ||
      truths[index].truth.iscrowd ||
      !in_area(truths[index].truth.area, lower, upper)
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
      records.push({
        score: candidate.detection.score,
        order: candidate.order,
        matched: best >= 0,
        ignored: match_ignored,
      })
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
  for step in 0..<10 {
    let threshold = 0.5 + step.to_double() * 0.05
    let all = evaluate_curve(
      dataset, detections, category_id, threshold, 0.0, 1.0e10, 100,
    )
    all_ap.push(all.ap)
    all_ar100.push(all.ar)
    all_ar1.push(
      evaluate_curve(
        dataset, detections, category_id, threshold, 0.0, 1.0e10, 1,
      ).ar,
    )
    all_ar10.push(
      evaluate_curve(
        dataset, detections, category_id, threshold, 0.0, 1.0e10, 10,
      ).ar,
    )
    let small = evaluate_curve(
      dataset, detections, category_id, threshold, 0.0, 1024.0, 100,
    )
    let medium = evaluate_curve(
      dataset, detections, category_id, threshold, 1024.0, 9216.0, 100,
    )
    let large = evaluate_curve(
      dataset, detections, category_id, threshold, 9216.0, 1.0e10, 100,
    )
    small_ap.push(small.ap)
    medium_ap.push(medium.ap)
    large_ap.push(large.ap)
    small_ar.push(small.ar)
    medium_ar.push(medium.ar)
    large_ar.push(large.ar)
    if step == 0 {
      ap50 = all.ap
    }
    if step == 5 {
      ap75 = all.ap
    }
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
  let image_ids : Map[Int, Bool] = Map([])
  let category_ids : Map[Int, Bool] = Map([])
  let detection_ids : Map[Int, Bool] = Map([])
  for image in dataset.images {
    image_ids[image.id] = true
  }
  for category in dataset.categories {
    category_ids[category.id] = true
  }
  let detections : Array[RankedDetection] = []
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
  }
  let classes : Array[ClassMetrics] = []
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
    let metrics = metrics_for_category(dataset, detections, category.id)
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
  }
}
