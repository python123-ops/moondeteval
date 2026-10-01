///|
extern "C" fn exit_process(code : Int) = "exit"

///|
async fn fail_command(message : String) -> Unit {
  @stdio.stderr..write(message).write("\n")
  exit_process(1)
}

///|
async fn main {
  let arguments = @env.args()
  if arguments.length() != 3 {
    fail_command("usage: moondeteval <ground-truth.json> <detections.json>")
    return
  }
  let ground_truth = @fs.read_file(arguments[1]).text()
  let detections = @fs.read_file(arguments[2]).text()
  let dataset = @moondeteval.parse_coco_dataset(ground_truth) catch {
    error => {
      fail_command("ground truth: " + error.message())
      return
    }
  }
  let predictions = @moondeteval.parse_coco_detections(detections) catch {
    error => {
      fail_command("detections: " + error.message())
      return
    }
  }
  let report = @moondeteval.evaluate(dataset, predictions) catch {
    error => {
      fail_command("evaluation: " + error.message())
      return
    }
  }
  @stdio.stdout..write(report.to_json_string()).write("\n")
}
