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
  assert_eq(
    @moondeteval.evaluate_masks_with_config(
      dataset,
      [prediction],
      config,
      max_iou_cache_pairs=0,
    ).to_json_string(),
    report.to_json_string(),
  )
  assert_eq(
    @moondeteval.compare_mask_predictions_with_config(
      dataset,
      [prediction],
      [],
      config,
      max_iou_cache_pairs=1,
    ).to_json_string(),
    @moondeteval.compare_mask_predictions_with_config(
      dataset,
      [prediction],
      [],
      config,
      max_iou_cache_pairs=0,
    ).to_json_string(),
  )
}

///|
test "source consumer parses COCO polygon masks with dataset canvas" {
  let dataset = @moondeteval.parse_coco_mask_dataset(
    "{\"images\":[{\"id\":5,\"width\":4,\"height\":4}],\"categories\":[{\"id\":7,\"name\":\"object\"}],\"annotations\":[{\"id\":9,\"image_id\":5,\"category_id\":7,\"area\":9,\"segmentation\":[[0,0,3,0,3,3,0,3]]}]}",
  )
  let predictions = @moondeteval.parse_coco_mask_detections_with_dataset(
    "[{\"image_id\":5,\"category_id\":7,\"score\":0.9,\"segmentation\":[[0,0,3,0,3,3,0,3]]}]",
    dataset,
  )
  assert_eq(predictions[0].mask().area(), 9)
  assert_eq(
    @moondeteval.evaluate_masks(dataset, predictions).summary().ap(),
    1.0,
  )
  let mask = @moondeteval.parse_coco_segmentation("[[0,0,3,0,3,3,0,3]]", 4, 4)
  assert_eq(
    mask.iou(
      @moondeteval.CocoRle::from_polygons(4, 4, [
        [0.0, 0.0, 3.0, 0.0, 3.0, 3.0, 0.0, 3.0],
      ]),
    ),
    1.0,
  )
}
