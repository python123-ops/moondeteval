///|
fn gate_fields(
  value : Json,
  allowed : Array[String],
  location : String,
) -> Map[String, Json] raise EvalError {
  guard value is Object(fields) else {
    raise InvalidConfig(location + " must be an object")
  }
  for key in fields.keys() {
    if !allowed.contains(key) {
      raise InvalidConfig(location + ": unknown field " + key)
    }
  }
  fields
}

///|
fn gate_string(
  fields : Map[String, Json],
  key : String,
  location : String,
) -> String raise EvalError {
  match fields.get(key) {
    Some(String(value)) => value
    _ => raise InvalidConfig(location + "." + key + " must be a string")
  }
}

///|
/// Parse a version-1 policy. Unknown fields are rejected to catch misspelled rules.
pub fn GatePolicy::from_json_string(
  source : String,
) -> GatePolicy raise EvalError {
  let json = @json.parse(source) catch {
    _ => raise InvalidConfig("gate policy must be valid JSON")
  }
  let fields = gate_fields(
    json,
    ["format_version", "undefined_policy", "rules"],
    "gate policy",
  )
  if gate_string(fields, "format_version", "gate policy") != "1" {
    raise InvalidConfig("unsupported gate policy format_version; expected 1")
  }
  let undefined_policy = if fields.contains("undefined_policy") {
    gate_string(fields, "undefined_policy", "gate policy")
  } else {
    "fail"
  }
  let entries = match fields.get("rules") {
    Some(Array(values)) if values.length() > 0 && values.length() <= 1000 =>
      values
    _ => raise InvalidConfig("gate policy.rules must contain 1 to 1000 rules")
  }
  let rules : Array[GateRule] = []
  for index, entry in entries {
    let location = "gate policy.rules[\{index}]"
    let rule = gate_fields(
      entry,
      ["kind", "metric", "threshold", "category_id"],
      location,
    )
    let kind = gate_string(rule, "kind", location)
    if kind != "minimum" && kind != "max_drop" {
      raise InvalidConfig(location + ".kind must be minimum or max_drop")
    }
    let metric = gate_string(rule, "metric", location)
    let threshold = match rule.get("threshold") {
      Some(Number(value, ..)) => value
      _ => raise InvalidConfig(location + ".threshold must be a JSON number")
    }
    let category : Int32? = match rule.get("category_id") {
      None | Some(Null) => None
      Some(value) => {
        guard value is Number(number, ..) &&
          finite(number) &&
          number >= -2147483648.0 &&
          number <= 2147483647.0 else {
          raise InvalidConfig(
            location + ".category_id must be null or a signed 32-bit integer",
          )
        }
        let id : Int32 = @json.from_json(value) catch {
          _ =>
            raise InvalidConfig(
              location + ".category_id must be null or a signed 32-bit integer",
            )
        }
        if id.to_double() != number {
          raise InvalidConfig(location + ".category_id must be an integer")
        }
        Some(id)
      }
    }
    rules.push(
      new_gate_rule(kind, metric, threshold, category) catch {
        error => raise InvalidConfig(location + ": " + error.message())
      },
    )
  }
  GatePolicy::new(rules, undefined_policy~)
}

///|
pub impl ToJson for GatePolicy with fn to_json(self : GatePolicy) -> Json {
  let rules = self.rules.map(rule => {
    let fields : Map[String, Json] = {
      "kind": Json::string(rule.kind),
      "metric": Json::string(rule.metric),
      "threshold": Json::number(rule.threshold),
      "category_id": match rule.category_id {
        Some(id) => Json(id)
        None => Json::null()
      },
    }
    Json::object(fields)
  })
  Json::object({
    "format_version": Json::string("1"),
    "undefined_policy": Json::string(self.undefined_policy),
    "rules": Json::array(rules),
  })
}

///|
pub extend GatePolicy with ToJson::{to_json}

///|
/// Serialize ordered rules, including explicit null for an overall scope.
pub fn GatePolicy::to_json_string(self : GatePolicy) -> String {
  self.to_json().stringify()
}
