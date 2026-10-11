///|
fn parse_counts(value : String) -> Array[Int] raise {
  let counts = []
  for part in value.split(",") {
    counts.push(@string.parse_int(part))
  }
  counts
}

///|
fn main raise {
  let args = @env.args()
  let (detection, truth) = if args.length() == 4 && args[1] == "--json" {
    (@moondeteval.parse_coco_rle(args[2]), @moondeteval.parse_coco_rle(args[3]))
  } else {
    if args.length() != 5 {
      abort(
        "expected height width detection-counts truth-counts or --json detection truth",
      )
    }
    let height = @string.parse_int(args[1])
    let width = @string.parse_int(args[2])
    (
      @moondeteval.CocoRle::new(height, width, parse_counts(args[3])),
      @moondeteval.CocoRle::new(height, width, parse_counts(args[4])),
    )
  }
  let result : Json = {
    "detection_area": @json.to_json(detection.area()),
    "truth_area": @json.to_json(truth.area()),
    "iou": @json.to_json(detection.iou(truth)),
    "crowd_iou": @json.to_json(detection.crowd_iou(truth)),
    "detection_counts": @json.to_json(detection.to_compressed()),
    "truth_counts": @json.to_json(truth.to_compressed()),
  }
  println(result.stringify())
}
