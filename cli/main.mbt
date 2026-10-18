///|
extern "C" fn exit_process(code : Int32) = "exit"

///|
async fn fail_command(message : String, code : Int32) -> Unit {
  @stdio.stderr..write(message).write("\n")
  exit_process(code)
}

///|
fn usage() -> String {
  "usage: moondeteval <ground-truth.json> <detections.json|manifest.json> [options]"
}

///|
fn help_text() -> String {
  usage() +
  "\n\nEvaluate COCO bbox/mask predictions or a YOLO bbox manifest against one ground-truth file.\n" +
  "\nInputs:\n  ground-truth.json            COCO ground truths\n  detections.json|manifest.json  COCO detections or YOLO manifest\n" +
  "\nOptions:\n  --iou-type bbox|segm          Evaluation geometry (default: bbox; segm requires COCO masks)\n  --prediction-format coco|yolo  Prediction input format (default: coco)\n  --compare OTHER.json          Compare a second prediction file\n  --compare-format coco|yolo     Second prediction format (default: coco)\n  --diagnostics                 Include matching decisions\n  --image-ranking               Include per-image results\n  --pr-curves                   Include precision-recall curves\n  --timings                     Print stage timings to stderr\n  --min-ap50 N                  Fail if AP50 is below N\n  --fail-on-warning             Fail on out-of-image warnings\n  --output PATH                 Write report to a new file\n  --max-input-bytes N           Limit each input file\n  --max-total-input-bytes N     Limit combined input size\n  --max-records N               Limit input records\n  --max-diagnostics N           Limit diagnostic entries\n  --max-report-bytes N          Limit report size\n  -h, --help                    Show this help\n" +
  "\nExamples (from source checkout):\n  moon run cli --target native -- examples/ground-truth.json examples/detections.json\n  moon run cli --target native -- examples/yolo/ground-truth.json examples/yolo/manifest.json --prediction-format yolo\n" +
  "\nExit codes: 0 success; 2 invalid input or usage; 3 quality gate failure.\n" +
  "\nMetric gates (source candidate; fraction units, tolerance 1e-12):\n  --gate-policy POLICY.json      Load a reusable policy (exclusive with inline rules)\n  --check-gate-policy POLICY.json  Validate policy only: moondeteval --check-gate-policy FILE\n  --min-metric METRIC=VALUE      Minimum overall metric\n  --max-metric-drop METRIC=VALUE  Maximum baseline minus candidate (requires --compare)\n  --min-class-metric ID:METRIC=VALUE  Minimum category metric\n  --max-class-drop ID:METRIC=VALUE  Maximum category drop (requires --compare)\n  --undefined-gate fail|skip      Undefined metric behavior (default: fail)\nRepeat metric rules up to 1000 times. Metric gates cannot be combined with --min-ap50.\nAll skipped rules still fail. Failed gates retain complete reports.\n"
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.length() == 2 &&
    (arguments[1] == "--help" || arguments[1] == "-h") {
    @stdio.stdout.write(help_text())
    return
  }
  if arguments.length() >= 2 && arguments[1] == "--check-gate-policy" {
    if arguments.length() != 3 {
      fail_command("usage: moondeteval --check-gate-policy POLICY.json", 2)
      return
    }
    let policy = load_gate_policy(arguments[2], 262144, 262144L) catch {
      error => {
        fail_command(error.message(), 2)
        return
      }
    }
    @stdio.stdout.write(policy.0.to_json_string() + "\n")
    return
  }
  if arguments.length() < 3 {
    fail_command(
      usage() + "\nRun moondeteval --help for options and examples.",
      2,
    )
    return
  }
  if arguments[1].has_prefix("-") || arguments[2].has_prefix("-") {
    fail_command(
      "expected ground-truth and prediction paths before options\nRun moondeteval --help for options and examples.",
      2,
    )
    return
  }
  let mut include_diagnostics = false
  let mut include_image_summaries = false
  let mut include_pr_curves = false
  let mut show_timings = false
  let mut fail_on_warning = false
  let mut comparison_path : String? = None
  let mut iou_type = "bbox"
  let mut seen_iou_type = false
  let mut prediction_format = "coco"
  let mut comparison_format = "coco"
  let mut seen_prediction_format = false
  let mut seen_comparison_format = false
  let mut minimum_ap50 : Double? = None
  let gate_rules : Array[@moondeteval.GateRule] = []
  let mut undefined_gate : String? = None
  let mut gate_policy_path : String? = None
  let mut output_path : String? = None
  let mut max_input_bytes = 67108864
  let mut max_total_input_bytes = 134217728
  let mut max_records = 100000
  let mut max_diagnostics = 100000
  let mut max_report_bytes = 67108864
  let mut index = 3
  while index < arguments.length() {
    match arguments[index] {
      "--gate-policy" => {
        if gate_policy_path is Some(_) || index + 1 >= arguments.length() {
          fail_command("--gate-policy requires one policy file, once", 2)
          return
        }
        gate_policy_path = Some(arguments[index + 1])
        index += 2
      }
      "--min-metric"
      | "--max-metric-drop"
      | "--min-class-metric"
      | "--max-class-drop" => {
        if index + 1 >= arguments.length() || gate_rules.length() >= 1000 {
          fail_command("gate option requires a value and at most 1000 rules", 2)
          return
        }
        let rule = parse_gate_rule(arguments[index], arguments[index + 1]) catch {
          error => {
            fail_command(error.message(), 2)
            return
          }
        }
        gate_rules.push(rule)
        index += 2
      }
      "--undefined-gate" => {
        if undefined_gate is Some(_) ||
          index + 1 >= arguments.length() ||
          (arguments[index + 1] != "fail" && arguments[index + 1] != "skip") {
          fail_command("--undefined-gate requires fail or skip, once", 2)
          return
        }
        undefined_gate = Some(arguments[index + 1])
        index += 2
      }
      "--iou-type" => {
        if seen_iou_type ||
          index + 1 >= arguments.length() ||
          (arguments[index + 1] != "bbox" && arguments[index + 1] != "segm") {
          fail_command("--iou-type requires bbox or segm, once", 2)
          return
        }
        iou_type = arguments[index + 1]
        seen_iou_type = true
        index += 2
      }
      "--diagnostics" => {
        if include_diagnostics {
          fail_command("--diagnostics may only be given once", 2)
          return
        }
        include_diagnostics = true
        index += 1
      }
      "--image-ranking" => {
        if include_image_summaries {
          fail_command("--image-ranking may only be given once", 2)
          return
        }
        include_image_summaries = true
        index += 1
      }
      "--pr-curves" => {
        if include_pr_curves {
          fail_command("--pr-curves may only be given once", 2)
          return
        }
        include_pr_curves = true
        index += 1
      }
      "--timings" => {
        if show_timings {
          fail_command("--timings may only be given once", 2)
          return
        }
        show_timings = true
        index += 1
      }
      "--fail-on-warning" => {
        if fail_on_warning {
          fail_command("--fail-on-warning may only be given once", 2)
          return
        }
        fail_on_warning = true
        index += 1
      }
      "--compare" => {
        if comparison_path is Some(_) ||
          index + 1 >= arguments.length() ||
          arguments[index + 1].is_empty() {
          fail_command("--compare requires one nonempty path", 2)
          return
        }
        comparison_path = Some(arguments[index + 1])
        index += 2
      }
      "--prediction-format" | "--compare-format" => {
        let option = arguments[index]
        if index + 1 >= arguments.length() ||
          (arguments[index + 1] != "coco" && arguments[index + 1] != "yolo") {
          fail_command(option + " requires coco or yolo", 2)
          return
        }
        if option == "--prediction-format" {
          if seen_prediction_format {
            fail_command(option + " may only be given once", 2)
            return
          }
          prediction_format = arguments[index + 1]
          seen_prediction_format = true
        } else {
          if seen_comparison_format {
            fail_command(option + " may only be given once", 2)
            return
          }
          comparison_format = arguments[index + 1]
          seen_comparison_format = true
        }
        index += 2
      }
      "--min-ap50" => {
        if minimum_ap50 is Some(_) || index + 1 >= arguments.length() {
          fail_command("--min-ap50 requires one value", 2)
          return
        }
        let value = @string.parse_double(arguments[index + 1]) catch {
          _ => {
            fail_command("--min-ap50 must be a number in [0,1]", 2)
            return
          }
        }
        if value.is_nan() || value.is_inf() || value < 0.0 || value > 1.0 {
          fail_command("--min-ap50 must be a finite number in [0,1]", 2)
          return
        }
        minimum_ap50 = Some(value)
        index += 2
      }
      "--output" => {
        if output_path is Some(_) ||
          index + 1 >= arguments.length() ||
          arguments[index + 1].is_empty() {
          fail_command("--output requires one nonempty path", 2)
          return
        }
        output_path = Some(arguments[index + 1])
        index += 2
      }
      "--max-input-bytes"
      | "--max-total-input-bytes"
      | "--max-records"
      | "--max-diagnostics"
      | "--max-report-bytes" => {
        let option = arguments[index]
        if index + 1 >= arguments.length() {
          fail_command(option + " requires a positive integer", 2)
          return
        }
        let value = @string.parse_int(arguments[index + 1]) catch {
          _ => {
            fail_command(option + " requires a positive integer", 2)
            return
          }
        }
        if value <= 0 {
          fail_command(option + " requires a positive integer", 2)
          return
        }
        if option == "--max-input-bytes" {
          max_input_bytes = value
        } else if option == "--max-total-input-bytes" {
          max_total_input_bytes = value
        } else if option == "--max-records" {
          max_records = value
        } else if option == "--max-diagnostics" {
          max_diagnostics = value
        } else {
          max_report_bytes = value
        }
        index += 2
      }
      _ => {
        fail_command("unknown option: " + arguments[index], 2)
        return
      }
    }
  }
  let input_timer = @bench.monotonic_clock_start()
  let mut policy_input_bytes = 0L
  let gate_policy = if gate_policy_path is Some(path) {
    if !gate_rules.is_empty() ||
      undefined_gate is Some(_) ||
      minimum_ap50 is Some(_) {
      fail_command(
        "--gate-policy cannot be combined with inline metric rules, --undefined-gate or --min-ap50",
        2,
      )
      return
    }
    let (policy, size) = load_gate_policy(
      path,
      max_input_bytes,
      max_total_input_bytes.to_int64(),
    ) catch {
      error => {
        fail_command(error.message(), 2)
        return
      }
    }
    if comparison_path is None &&
      policy.rules().any(rule => rule.kind() == "max_drop") {
      fail_command("maximum-drop gates require --compare", 2)
      return
    }
    policy_input_bytes = size
    Some(policy)
  } else if gate_rules.is_empty() {
    if undefined_gate is Some(_) {
      fail_command("--undefined-gate requires metric gate rules", 2)
      return
    }
    None
  } else {
    if minimum_ap50 is Some(_) {
      fail_command(
        "--min-ap50 cannot be combined with metric gate rules; use --min-metric ap50=VALUE",
        2,
      )
      return
    }
    if comparison_path is None &&
      gate_rules.any(rule => rule.kind() == "max_drop") {
      fail_command("maximum-drop gates require --compare", 2)
      return
    }
    Some(
      @moondeteval.GatePolicy::new(
        gate_rules,
        undefined_policy=undefined_gate.unwrap_or("fail"),
      ) catch {
        error => {
          fail_command(error.message(), 2)
          return
        }
      },
    )
  }
  if seen_comparison_format && comparison_path is None {
    fail_command("--compare-format requires --compare", 2)
    return
  }
  if iou_type == "segm" &&
    (
      prediction_format != "coco" ||
      (comparison_path is Some(_) && comparison_format != "coco")
    ) {
    fail_command(
      "--iou-type segm requires COCO masks predictions; YOLO supports bbox only",
      2,
    )
    return
  }
  match output_path {
    Some(path) => {
      if path == arguments[1] || path == arguments[2] {
        fail_command("output path must differ from both input paths", 2)
        return
      }
      if comparison_path == Some(path) {
        fail_command("output path must differ from comparison input", 2)
        return
      }
      let already_exists = @fs.exists(path) catch {
        error => {
          fail_command("cannot inspect output " + path + ": \{error}", 2)
          return
        }
      }
      if already_exists {
        fail_command("output already exists: " + path, 2)
        return
      }
    }
    None => ()
  }
  let sources : Array[String] = []
  let mut input_bytes = policy_input_bytes
  let input_paths = [arguments[1], arguments[2]]
  match comparison_path {
    Some(path) => input_paths.push(path)
    None => ()
  }
  for path in input_paths {
    let (content, size) = read_limited_input(
      path,
      max_input_bytes,
      max_total_input_bytes.to_int64() - input_bytes,
    ) catch {
      error => {
        fail_command(error.message(), 2)
        return
      }
    }
    input_bytes += size
    sources.push(content)
  }
  let (input, extra_bytes) = load_evaluation_input(
    sources,
    input_paths,
    iou_type,
    prediction_format,
    comparison_format,
    max_input_bytes,
    max_total_input_bytes.to_int64() - input_bytes,
    max_records,
  ) catch {
    error => {
      fail_command(error.message(), 2)
      return
    }
  }
  input_bytes += extra_bytes
  let (
    metadata_records,
    truth_records,
    prediction_records,
    comparison_records_with_truths,
  ) = input.sizes()
  let comparison_records = if sources.length() == 3 {
    comparison_records_with_truths - truth_records
  } else {
    0
  }
  let records = metadata_records +
    truth_records +
    prediction_records +
    comparison_records
  if records > max_records {
    fail_command(
      "input has \{records} records, exceeding --max-records \{max_records}",
      2,
    )
    return
  }
  let diagnostic_records = prediction_records +
    truth_records +
    comparison_records_with_truths
  if include_diagnostics &&
    diagnostic_records.to_int64() * 10L > max_diagnostics.to_int64() {
    fail_command(
      "diagnostic upper bound exceeds --max-diagnostics \{max_diagnostics}; raise the limit explicitly if intended",
      2,
    )
    return
  }
  let input_us = @bench.monotonic_clock_end(input_timer)
  let (
    report_json,
    actual_ap50,
    warning_count,
    summary_line,
    evaluation_us,
    serialization_us,
    metric_gates,
  ) = try {
    let config = @moondeteval.EvalConfig::new(
      @moondeteval.EvalConfig::coco().iou_thresholds(),
      include_diagnostics~,
      include_image_summaries~,
      include_pr_curves~,
    )
    let evaluation_timer = @bench.monotonic_clock_start()
    let evaluated = input.evaluate(config)
    let evaluation_us = @bench.monotonic_clock_end(evaluation_timer)
    let metric_gates = match gate_policy {
      Some(policy) => Some(evaluated.metric_gates(policy))
      None => None
    }
    match evaluated {
      Paired(comparison) => {
        let baseline = comparison.baseline()
        let candidate = comparison.candidate()
        let mut warning_count = baseline.quality_warnings().length()
        for warning in candidate.quality_warnings() {
          if warning.source() != "ground_truth" {
            warning_count += 1
          }
        }
        let serialization_timer = @bench.monotonic_clock_start()
        let report_json = evaluated.json_with_gates(metric_gates)
        let serialization_us = @bench.monotonic_clock_end(serialization_timer)
        (
          report_json,
          candidate.summary().ap50(),
          warning_count,
          "baseline AP50=\{baseline.summary().ap50()} candidate AP50=\{candidate.summary().ap50()}\n",
          evaluation_us,
          serialization_us,
          metric_gates,
        )
      }
      Single(report) => {
        let serialization_timer = @bench.monotonic_clock_start()
        let report_json = evaluated.json_with_gates(metric_gates)
        let serialization_us = @bench.monotonic_clock_end(serialization_timer)
        (
          report_json,
          report.summary().ap50(),
          report.quality_warnings().length(),
          "AP=\{report.summary().ap()} AP50=\{report.summary().ap50()} AR100=\{report.summary().ar100()}\n",
          evaluation_us,
          serialization_us,
          metric_gates,
        )
      }
    }
  } catch {
    error => {
      fail_command("evaluation: " + error.message(), 2)
      return
    }
  }
  let output_timer = @bench.monotonic_clock_start()
  let output = report_json + "\n"
  if output.length() > max_report_bytes {
    fail_command("report exceeds --max-report-bytes \{max_report_bytes}", 2)
    return
  }
  match output_path {
    Some(path) => {
      let temporary = path + ".moondeteval.tmp"
      let file = @fs.create(temporary, allow_existing=false) catch {
        error => {
          fail_command(
            "cannot create temporary output " + temporary + ": \{error}",
            2,
          )
          return
        }
      }
      try {
        file.write(output)
        file.sync()
        file.close()
        @fs.rename(temporary, path, replace=false)
      } catch {
        error => {
          file.close()
          @fs.remove(temporary) catch {
            _ => ()
          }
          fail_command("cannot write output " + path + ": \{error}", 2)
          return
        }
      }
      @stdio.stdout.write(summary_line)
    }
    None => @stdio.stdout.write(output)
  }
  if show_timings {
    let output_us = @bench.monotonic_clock_end(output_timer)
    @stdio.stderr.write(
      "timings_us input=\{input_us} evaluation=\{evaluation_us} serialization=\{serialization_us} output=\{output_us}\n",
    )
  }
  match metric_gates {
    Some(gates) =>
      if gates.status() == "failed" {
        fail_command("metric gates failed: " + gates.reason(), 3)
        return
      }
    None => ()
  }
  match minimum_ap50 {
    Some(minimum) =>
      if actual_ap50 < 0.0 || actual_ap50 < minimum {
        fail_command(
          "AP50 gate failed: actual=\{actual_ap50}, minimum=\{minimum}",
          3,
        )
        return
      }
    None => ()
  }
  if fail_on_warning && warning_count > 0 {
    fail_command(
      "quality gate failed: \{warning_count} out-of-image warning(s)",
      3,
    )
  }
}
