///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn fail_command(message : String, code : Int) -> Unit {
  @stdio.stderr..write(message).write("\n")
  exit_process(code)
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.length() < 3 {
    fail_command(
      "usage: moondeteval <ground-truth.json> <detections.json|manifest.json> [--prediction-format coco|yolo] [--compare OTHER.json] [--compare-format coco|yolo] [--diagnostics] [--image-ranking] [--min-ap50 N] [--fail-on-warning] [--output PATH] [--max-input-bytes N] [--max-total-input-bytes N] [--max-records N] [--max-diagnostics N] [--max-report-bytes N]",
      2,
    )
    return
  }
  let mut include_diagnostics = false
  let mut include_image_summaries = false
  let mut fail_on_warning = false
  let mut comparison_path : String? = None
  let mut prediction_format = "coco"
  let mut comparison_format = "coco"
  let mut seen_prediction_format = false
  let mut seen_comparison_format = false
  let mut minimum_ap50 : Double? = None
  let mut output_path : String? = None
  let mut max_input_bytes = 67108864
  let mut max_total_input_bytes = 134217728
  let mut max_records = 100000
  let mut max_diagnostics = 100000
  let mut max_report_bytes = 67108864
  let mut index = 3
  while index < arguments.length() {
    match arguments[index] {
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
  if seen_comparison_format && comparison_path is None {
    fail_command("--compare-format requires --compare", 2)
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
  let mut input_bytes = 0L
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
  let ground_truth = sources[0]
  let dataset = @moondeteval.parse_coco_dataset(ground_truth) catch {
    error => {
      fail_command("ground truth " + arguments[1] + ": " + error.message(), 2)
      return
    }
  }
  let (predictions, prediction_bytes) = load_predictions(
    sources[1],
    arguments[2],
    prediction_format,
    dataset,
    max_input_bytes,
    max_total_input_bytes.to_int64() - input_bytes,
    max_records,
  ) catch {
    error => {
      fail_command(error.message(), 2)
      return
    }
  }
  input_bytes += prediction_bytes
  let comparison_predictions = if sources.length() == 3 {
    let (parsed, comparison_bytes) = load_predictions(
      sources[2],
      input_paths[2],
      comparison_format,
      dataset,
      max_input_bytes,
      max_total_input_bytes.to_int64() - input_bytes,
      max_records,
    ) catch {
      error => {
        fail_command(error.message(), 2)
        return
      }
    }
    input_bytes += comparison_bytes
    Some(parsed)
  } else {
    None
  }
  let comparison_records = match comparison_predictions {
    Some(other) => other.length()
    None => 0
  }
  let records = dataset.images().length() +
    dataset.categories().length() +
    dataset.truths().length() +
    predictions.length() +
    comparison_records
  if records > max_records {
    fail_command(
      "input has \{records} records, exceeding --max-records \{max_records}",
      2,
    )
    return
  }
  let comparison_diagnostic_records = if comparison_predictions is Some(_) {
    comparison_records + dataset.truths().length()
  } else {
    0
  }
  let diagnostic_records = predictions.length() +
    dataset.truths().length() +
    comparison_diagnostic_records
  if include_diagnostics &&
    diagnostic_records.to_int64() * 10L > max_diagnostics.to_int64() {
    fail_command(
      "diagnostic upper bound exceeds --max-diagnostics \{max_diagnostics}; raise the limit explicitly if intended",
      2,
    )
    return
  }
  let (report_json, actual_ap50, warning_count, summary_line) = try {
    match comparison_predictions {
      Some(other) => {
        let config = @moondeteval.EvalConfig::new(
          @moondeteval.EvalConfig::coco().iou_thresholds(),
          include_diagnostics~,
          include_image_summaries~,
        )
        let comparison = @moondeteval.compare_predictions_with_config(
          dataset, predictions, other, config,
        )
        let baseline = comparison.baseline()
        let candidate = comparison.candidate()
        let mut warning_count = baseline.quality_warnings().length()
        for warning in candidate.quality_warnings() {
          if warning.source() != "ground_truth" {
            warning_count += 1
          }
        }
        (
          comparison.to_json_string(),
          candidate.summary().ap50(),
          warning_count,
          "baseline AP50=\{baseline.summary().ap50()} candidate AP50=\{candidate.summary().ap50()}\n",
        )
      }
      None => {
        let config = @moondeteval.EvalConfig::new(
          @moondeteval.EvalConfig::coco().iou_thresholds(),
          include_diagnostics~,
          include_image_summaries~,
        )
        let report = @moondeteval.evaluate_with_config(
          dataset, predictions, config,
        )
        (
          report.to_json_string(),
          report.summary().ap50(),
          report.quality_warnings().length(),
          "AP=\{report.summary().ap()} AP50=\{report.summary().ap50()} AR100=\{report.summary().ar100()}\n",
        )
      }
    }
  } catch {
    error => {
      fail_command("evaluation: " + error.message(), 2)
      return
    }
  }
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
