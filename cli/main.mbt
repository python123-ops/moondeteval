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
      "usage: moondeteval <ground-truth.json> <detections.json> [--diagnostics] [--min-ap50 N]",
      2,
    )
    return
  }
  let mut include_diagnostics = false
  let mut minimum_ap50 : Double? = None
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
      _ => {
        fail_command("unknown option: " + arguments[index], 2)
        return
      }
    }
  }
  let ground_truth = @fs.read_file(arguments[1]).text()
  let detections = @fs.read_file(arguments[2]).text()
  let dataset = @moondeteval.parse_coco_dataset(ground_truth) catch {
    error => {
      fail_command("ground truth: " + error.message(), 2)
      return
    }
  }
  let predictions = @moondeteval.parse_coco_detections(detections) catch {
    error => {
      fail_command("detections: " + error.message(), 2)
      return
    }
  }
  let report = try {
    if include_diagnostics {
      @moondeteval.evaluate_with_diagnostics(dataset, predictions)
    } else {
      @moondeteval.evaluate(dataset, predictions)
    }
  } catch {
    error => {
      fail_command("evaluation: " + error.message(), 2)
      return
    }
  }
  @stdio.stdout..write(report.to_json_string()).write("\n")
  match minimum_ap50 {
    Some(minimum) => {
      let actual = report.summary().ap50()
      if actual < 0.0 || actual < minimum {
        fail_command(
          "AP50 gate failed: actual=\{actual}, minimum=\{minimum}",
          3,
        )
      }
    }
    None => ()
  }
}
