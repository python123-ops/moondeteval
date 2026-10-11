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
  let (detection, truth) = if args.length() == 6 && args[1] == "--segmentation" {
    let height = @string.parse_int(args[2])
    let width = @string.parse_int(args[3])
    (
      @moondeteval.parse_coco_segmentation(args[4], height, width),
      @moondeteval.parse_coco_segmentation(args[5], height, width),
    )
  } else if args.length() == 4 && args[1] == "--json" {
    (@moondeteval.parse_coco_rle(args[2]), @moondeteval.parse_coco_rle(args[3]))
  } else {
    if args.length() != 5 {
      abort(
        "expected height width detection-counts truth-counts, --json detection truth, or --segmentation height width detection truth",
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
