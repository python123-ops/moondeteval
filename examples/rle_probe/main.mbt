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
  if args.length() != 5 {
    abort("expected height width detection-counts truth-counts")
  }
  let height = @string.parse_int(args[1])
  let width = @string.parse_int(args[2])
  let detection = @moondeteval.CocoRle::new(
    height,
    width,
    parse_counts(args[3]),
  )
  let truth = @moondeteval.CocoRle::new(height, width, parse_counts(args[4]))
  println(
    "\{detection.area()} \{truth.area()} \{detection.iou(truth)} \{detection.crowd_iou(truth)}",
  )
}
