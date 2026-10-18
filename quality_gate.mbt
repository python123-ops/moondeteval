///|
/// A minimum value or maximum baseline-minus-candidate drop, in fraction units.
pub struct GateRule {
  kind : String
  metric : String
  threshold : Double
  category_id : Int32?
} derive(ToJson)

///|
pub extend GateRule with ToJson::{to_json}

///|
fn new_gate_rule(
  kind : String,
  metric : String,
  threshold : Double,
  category_id : Int32?,
) -> GateRule raise EvalError {
  if ![
      "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large", "ar1", "ar10", "ar100",
      "ar_small", "ar_medium", "ar_large",
    ].contains(metric) {
    raise InvalidConfig("unknown gate metric: " + metric)
  }
  if !finite(threshold) || threshold < 0.0 || threshold > 1.0 {
    raise InvalidConfig("gate threshold must be finite and in [0,1]")
  }
  { kind, metric, threshold, category_id, }
}

///|
pub fn GateRule::minimum(
  metric : String,
  threshold : Double,
  category_id? : Int32,
) -> GateRule raise EvalError {
  new_gate_rule("minimum", metric, threshold, category_id)
}

///|
pub fn GateRule::max_drop(
  metric : String,
  threshold : Double,
  category_id? : Int32,
) -> GateRule raise EvalError {
  new_gate_rule("max_drop", metric, threshold, category_id)
}

///|
pub fn GateRule::kind(self : GateRule) -> String {
  self.kind
}

///|
pub fn GateRule::metric(self : GateRule) -> String {
  self.metric
}

///|
pub fn GateRule::threshold(self : GateRule) -> Double {
  self.threshold
}

///|
pub fn GateRule::category_id(self : GateRule) -> Int32? {
  self.category_id
}

///|
pub struct GatePolicy {
  rules : Array[GateRule]
  undefined_policy : String
}

///|
pub fn GatePolicy::new(
  rules : Array[GateRule],
  undefined_policy~ : String = "fail",
) -> GatePolicy raise EvalError {
  if rules.is_empty() || rules.length() > 1000 {
    raise InvalidConfig("gate policy must contain 1 to 1000 rules")
  }
  if undefined_policy != "fail" && undefined_policy != "skip" {
    raise InvalidConfig("undefined gate policy must be fail or skip")
  }
  let seen : Map[String, Bool] = Map([])
  for rule in rules {
    let scope = match rule.category_id {
      Some(id) => "category=\{id}"
      None => "overall"
    }
    let key = rule.kind + ":" + rule.metric + ":" + scope
    if seen.contains(key) {
      raise InvalidConfig("duplicate gate rule: " + key)
    }
    seen[key] = true
  }
  { rules: rules.copy(), undefined_policy, }
}

///|
pub fn GatePolicy::rules(self : GatePolicy) -> Array[GateRule] {
  self.rules.copy()
}

///|
pub fn GatePolicy::undefined_policy(self : GatePolicy) -> String {
  self.undefined_policy
}

///|
pub struct GateCheck {
  kind : String
  metric : String
  category_id : Int32?
  threshold : Double
  baseline : Double?
  candidate : Double?
  drop : Double?
  status : String
  reason : String
}

///|
pub impl ToJson for GateCheck with fn to_json(self : GateCheck) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["kind"] = Json::string(self.kind)
  fields["metric"] = Json::string(self.metric)
  fields["category_id"] = match self.category_id {
    Some(id) => Json(id)
    None => Json::null()
  }
  fields["threshold"] = Json::number(self.threshold)
  fields["baseline"] = optional_metric_json(self.baseline)
  fields["candidate"] = optional_metric_json(self.candidate)
  fields["drop"] = optional_metric_json(self.drop)
  fields["status"] = Json::string(self.status)
  fields["reason"] = Json::string(self.reason)
  Json::object(fields)
}

///|
pub extend GateCheck with ToJson::{to_json}

///|
pub fn GateCheck::kind(self : GateCheck) -> String {
  self.kind
}

///|
pub fn GateCheck::metric(self : GateCheck) -> String {
  self.metric
}

///|
pub fn GateCheck::category_id(self : GateCheck) -> Int32? {
  self.category_id
}

///|
pub fn GateCheck::threshold(self : GateCheck) -> Double {
  self.threshold
}

///|
pub fn GateCheck::baseline(self : GateCheck) -> Double? {
  self.baseline
}

///|
pub fn GateCheck::candidate(self : GateCheck) -> Double? {
  self.candidate
}

///|
pub fn GateCheck::drop(self : GateCheck) -> Double? {
  self.drop
}

///|
pub fn GateCheck::status(self : GateCheck) -> String {
  self.status
}

///|
pub fn GateCheck::reason(self : GateCheck) -> String {
  self.reason
}

///|
pub struct GateReport {
  format_version : String
  status : String
  undefined_policy : String
  reason : String
  checks : Array[GateCheck]
} derive(ToJson)

///|
pub extend GateReport with ToJson::{to_json}

///|
pub fn GateReport::to_json_string(self : GateReport) -> String {
  self.to_json().stringify()
}

///|
pub fn GateReport::status(self : GateReport) -> String {
  self.status
}

///|
pub fn GateReport::reason(self : GateReport) -> String {
  self.reason
}

///|
pub fn GateReport::undefined_policy(self : GateReport) -> String {
  self.undefined_policy
}

///|
pub fn GateReport::checks(self : GateReport) -> Array[GateCheck] {
  self.checks.copy()
}

///|
fn gate_metric(metrics : Metrics, name : String) -> Double {
  match name {
    "ap" => metrics.ap
    "ap50" => metrics.ap50
    "ap75" => metrics.ap75
    "ap_small" => metrics.ap_small
    "ap_medium" => metrics.ap_medium
    "ap_large" => metrics.ap_large
    "ar1" => metrics.ar1
    "ar10" => metrics.ar10
    "ar100" => metrics.ar100
    "ar_small" => metrics.ar_small
    "ar_medium" => metrics.ar_medium
    "ar_large" => metrics.ar_large
    _ => abort("validated gate metric")
  }
}

///|
fn gate_classes(report : EvaluationReport) -> Map[Int32, Metrics] {
  let result = Map([])
  for item in report.classes {
    result[item.category_id] = item.metrics
  }
  result
}

///|
fn gate_value(
  report : EvaluationReport,
  classes : Map[Int32, Metrics],
  rule : GateRule,
) -> Double? raise EvalError {
  let metrics = match rule.category_id {
    None => report.summary
    Some(id) =>
      match classes.get(id) {
        Some(metrics) => metrics
        None => raise InvalidConfig("unknown gate category: \{id}")
      }
  }
  let value = gate_metric(metrics, rule.metric)
  if value < 0.0 {
    None
  } else {
    Some(value)
  }
}

///|
fn check_metric_gates(
  candidate : EvaluationReport,
  baseline : EvaluationReport?,
  policy : GatePolicy,
) -> GateReport raise EvalError {
  if baseline is None && policy.rules.any(rule => rule.kind == "max_drop") {
    raise InvalidConfig("maximum-drop gates require a comparison report")
  }
  let candidate_classes = gate_classes(candidate)
  let baseline_classes = match baseline {
    Some(report) => gate_classes(report)
    None => Map([])
  }
  let checks : Array[GateCheck] = []
  let mut failed = false
  let mut evaluated = 0
  for rule in policy.rules {
    let actual = gate_value(candidate, candidate_classes, rule)
    let before = match baseline {
      Some(report) => gate_value(report, baseline_classes, rule)
      None => None
    }
    let drop = match (before, actual) {
      (Some(left), Some(right)) => Some(left - right)
      _ => None
    }
    let (status, reason) = if actual is None ||
      (rule.kind == "max_drop" && before is None) {
      (
        if policy.undefined_policy == "skip" {
          "skipped"
        } else {
          "failed"
        },
        if actual is None {
          "undefined_candidate"
        } else {
          "undefined_baseline"
        },
      )
    } else {
      evaluated += 1
      let passed = match (rule.kind, actual, drop) {
        ("minimum", Some(value), _) => value + 1.0e-12 >= rule.threshold
        ("max_drop", _, Some(value)) => value <= rule.threshold + 1.0e-12
        _ => false
      }
      (
        if passed {
          "passed"
        } else {
          "failed"
        },
        if passed {
          "ok"
        } else if rule.kind == "minimum" {
          "below_minimum"
        } else {
          "drop_exceeded"
        },
      )
    }
    if status == "failed" {
      failed = true
    }
    checks.push({
      kind: rule.kind,
      metric: rule.metric,
      category_id: rule.category_id,
      threshold: rule.threshold,
      baseline: before,
      candidate: actual,
      drop,
      status,
      reason,
    })
  }
  {
    format_version: "1",
    status: if failed || evaluated == 0 {
      "failed"
    } else {
      "passed"
    },
    undefined_policy: policy.undefined_policy,
    reason: if evaluated == 0 && !failed {
      "all_skipped"
    } else if failed {
      "rules_failed"
    } else {
      "ok"
    },
    checks,
  }
}

///|
/// Check absolute rules on this report. Drop rules require ComparisonReport.
pub fn EvaluationReport::check_gates(
  self : EvaluationReport,
  policy : GatePolicy,
) -> GateReport raise EvalError {
  check_metric_gates(self, None, policy)
}

///|
/// Check the candidate using the baseline from the same dataset/configuration.
pub fn ComparisonReport::check_gates(
  self : ComparisonReport,
  policy : GatePolicy,
) -> GateReport raise EvalError {
  check_metric_gates(self.candidate, Some(self.baseline), policy)
}
