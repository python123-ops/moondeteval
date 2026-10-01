///|
/// A paired metric difference. Undefined COCO values are JSON null here.
pub struct MetricChange {
  name : String
  baseline : Double?
  candidate : Double?
  delta : Double?
}

///|
pub impl ToJson for MetricChange with fn to_json(self : MetricChange) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(self.name)
  fields["baseline"] = optional_metric_json(self.baseline)
  fields["candidate"] = optional_metric_json(self.candidate)
  fields["delta"] = optional_metric_json(self.delta)
  Json::object(fields)
}

///|
pub extend MetricChange with ToJson::{to_json}

///|
fn optional_metric_json(value : Double?) -> Json {
  match value {
    Some(number) => Json::number(number)
    None => Json::null()
  }
}

///|
pub fn MetricChange::name(self : MetricChange) -> String {
  self.name
}

///|
pub fn MetricChange::baseline(self : MetricChange) -> Double? {
  self.baseline
}

///|
pub fn MetricChange::candidate(self : MetricChange) -> Double? {
  self.candidate
}

///|
pub fn MetricChange::delta(self : MetricChange) -> Double? {
  self.delta
}

///|
/// Category values use the same metric order as the overall comparison.
pub struct ClassComparison {
  category_id : Int
  metrics : Array[MetricChange]
} derive(ToJson)

///|
pub extend ClassComparison with ToJson::{to_json}

///|
pub fn ClassComparison::category_id(self : ClassComparison) -> Int {
  self.category_id
}

///|
pub fn ClassComparison::metrics(self : ClassComparison) -> Array[MetricChange] {
  self.metrics.copy()
}

///|
/// Both evaluations share one dataset and one configuration.
pub struct ComparisonReport {
  schema_version : String
  baseline : EvaluationReport
  candidate : EvaluationReport
  metrics : Array[MetricChange]
  classes : Array[ClassComparison]
} derive(ToJson)

///|
pub extend ComparisonReport with ToJson::{to_json}

///|
pub fn ComparisonReport::to_json_string(self : ComparisonReport) -> String {
  @json.to_json(self).stringify()
}

///|
pub fn ComparisonReport::baseline(self : ComparisonReport) -> EvaluationReport {
  self.baseline
}

///|
pub fn ComparisonReport::candidate(self : ComparisonReport) -> EvaluationReport {
  self.candidate
}

///|
pub fn ComparisonReport::metrics(
  self : ComparisonReport,
) -> Array[MetricChange] {
  self.metrics.copy()
}

///|
pub fn ComparisonReport::classes(
  self : ComparisonReport,
) -> Array[ClassComparison] {
  self.classes.copy()
}

///|
fn metric_change(
  name : String,
  baseline : Double,
  candidate : Double,
) -> MetricChange {
  let left = if baseline < 0.0 { None } else { Some(baseline) }
  let right = if candidate < 0.0 { None } else { Some(candidate) }
  {
    name,
    baseline: left,
    candidate: right,
    delta: if baseline < 0.0 || candidate < 0.0 {
      None
    } else {
      Some(candidate - baseline)
    },
  }
}

///|
fn metric_changes(
  baseline : Metrics,
  candidate : Metrics,
) -> Array[MetricChange] {
  [
    metric_change("ap", baseline.ap, candidate.ap),
    metric_change("ap50", baseline.ap50, candidate.ap50),
    metric_change("ap75", baseline.ap75, candidate.ap75),
    metric_change("ap_small", baseline.ap_small, candidate.ap_small),
    metric_change("ap_medium", baseline.ap_medium, candidate.ap_medium),
    metric_change("ap_large", baseline.ap_large, candidate.ap_large),
    metric_change("ar1", baseline.ar1, candidate.ar1),
    metric_change("ar10", baseline.ar10, candidate.ar10),
    metric_change("ar100", baseline.ar100, candidate.ar100),
    metric_change("ar_small", baseline.ar_small, candidate.ar_small),
    metric_change("ar_medium", baseline.ar_medium, candidate.ar_medium),
    metric_change("ar_large", baseline.ar_large, candidate.ar_large),
  ]
}

///|
/// Compare two prediction arrays against exactly the same ground truths.
pub fn compare_predictions(
  dataset : Dataset,
  baseline : Array[Detection],
  candidate : Array[Detection],
) -> ComparisonReport raise EvalError {
  compare_predictions_with_config(
    dataset,
    baseline,
    candidate,
    EvalConfig::coco(),
  )
}

///|
/// Compare with a shared IoU/diagnostic/ignore configuration.
pub fn compare_predictions_with_config(
  dataset : Dataset,
  baseline : Array[Detection],
  candidate : Array[Detection],
  config : EvalConfig,
) -> ComparisonReport raise EvalError {
  let left = evaluate_with_config(dataset, baseline, config)
  let right = evaluate_with_config(dataset, candidate, config)
  let classes : Array[ClassComparison] = []
  for index in 0..<left.classes.length() {
    classes.push({
      category_id: left.classes[index].category_id,
      metrics: metric_changes(
        left.classes[index].metrics,
        right.classes[index].metrics,
      ),
    })
  }
  {
    schema_version: "0.1.0",
    baseline: left,
    candidate: right,
    metrics: metric_changes(left.summary, right.summary),
    classes,
  }
}
