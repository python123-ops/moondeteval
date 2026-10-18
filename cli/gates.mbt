///|
fn parse_gate_rule(
  option : String,
  text : String,
) -> @moondeteval.GateRule raise @moondeteval.EvalError {
  let parts = text.split("=").to_array()
  if parts.length() != 2 {
    raise @moondeteval.InvalidConfig(
      option + " requires METRIC=VALUE or CATEGORY:METRIC=VALUE",
    )
  }
  let threshold = @string.parse_double(parts[1].to_owned()) catch {
    _ =>
      raise @moondeteval.InvalidConfig(
        "gate threshold must be a finite fraction in [0,1]",
      )
  }
  let scoped = option == "--min-class-metric" || option == "--max-class-drop"
  let (metric, category) = if scoped {
    let scope = parts[0].split(":").to_array()
    if scope.length() != 2 {
      raise @moondeteval.InvalidConfig(
        option + " requires CATEGORY:METRIC=VALUE",
      )
    }
    let id = @string.parse_int(scope[0].to_owned()) catch {
      _ =>
        raise @moondeteval.InvalidConfig(
          "gate category must be a signed 32-bit integer",
        )
    }
    (scope[1].to_owned(), Some(id))
  } else {
    (parts[0].to_owned(), None)
  }
  if option == "--min-metric" || option == "--min-class-metric" {
    match category {
      Some(id) =>
        @moondeteval.GateRule::minimum(metric, threshold, category_id=id)
      None => @moondeteval.GateRule::minimum(metric, threshold)
    }
  } else {
    match category {
      Some(id) =>
        @moondeteval.GateRule::max_drop(metric, threshold, category_id=id)
      None => @moondeteval.GateRule::max_drop(metric, threshold)
    }
  }
}

///|
fn CliResult::metric_gates(
  self : CliResult,
  policy : @moondeteval.GatePolicy,
) -> @moondeteval.GateReport raise @moondeteval.EvalError {
  match self {
    Single(report) => report.check_gates(policy)
    Paired(report) => report.check_gates(policy)
  }
}

///|
fn CliResult::json_with_gates(
  self : CliResult,
  gates : @moondeteval.GateReport?,
) -> String {
  let report = match self {
    Single(report) => report.to_json()
    Paired(report) => report.to_json()
  }
  match (report, gates) {
    (Object(fields), Some(gates)) => {
      fields["metric_gates"] = gates.to_json()
      Json::object(fields).stringify()
    }
    _ => report.stringify()
  }
}
