///|
test "source consumer evaluates masks through public types and config" {
  let mask = @moondeteval.CocoRle::new(2, 2, [0, 1, 2, 1])
  let dataset = @moondeteval.MaskDataset::new(
    [@moondeteval.Image::new(1, 2, 2)],
    [@moondeteval.Category::new(7, "mask")],
    [@moondeteval.MaskGroundTruth::new(99L, 1, 7, mask, area=2.0)],
  )
  let prediction = @moondeteval.MaskDetection::new(0, 1, 7, mask, 0.9)
  let config = @moondeteval.EvalConfig::new(
    [0.5, 0.75],
    ignore_policy="coco_segm",
    include_pr_curves=true,
  )
  let report = @moondeteval.evaluate_masks_with_config(
    dataset,
    [prediction],
    config,
  )
  assert_eq(report.summary().ap(), 1.0)
  assert_eq(report.iou_type(), "segm")
  assert_eq(report.pr_curves().length(), 2)
}
