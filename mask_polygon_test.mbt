///|
test "polygon integer rectangle has exact COCO column major encoding" {
  let mask = @moondeteval.CocoRle::from_polygons(4, 4, [
    [0.0, 0.0, 3.0, 0.0, 3.0, 3.0, 0.0, 3.0],
  ])
  assert_eq(mask.area(), 9)
  assert_eq(mask.to_compressed(), "0310004")
  assert_eq(
    mask.iou(@moondeteval.CocoRle::new(4, 4, [0, 3, 1, 3, 1, 3, 5])),
    1.0,
  )
}

///|
test "polygon rings use union including reverse winding nested rings" {
  let outer = [0.0, 0.0, 4.0, 0.0, 4.0, 4.0, 0.0, 4.0]
  let inner = [1.0, 1.0, 1.0, 3.0, 3.0, 3.0, 3.0, 1.0]
  assert_eq(
    @moondeteval.CocoRle::from_polygons(4, 4, [outer, inner]).area(),
    16,
  )
  let a = [0.0, 0.0, 2.0, 0.0, 2.0, 2.0, 0.0, 2.0]
  let b = [1.0, 1.0, 3.0, 1.0, 3.0, 3.0, 1.0, 3.0]
  assert_eq(@moondeteval.CocoRle::from_polygons(4, 4, [a, b]).area(), 7)
}

///|
test "polygon clipping and repeated closing vertices preserve mask" {
  let mask = @moondeteval.CocoRle::from_polygons(4, 4, [
    [-2.0, -2.0, 6.0, -2.0, 6.0, 6.0, -2.0, 6.0, -2.0, -2.0],
  ])
  assert_eq(mask.area(), 16)
  let outside = @moondeteval.CocoRle::from_polygons(4, 4, [
    [-4.0, -4.0, -2.0, -4.0, -2.0, -2.0, -4.0, -2.0],
  ])
  assert_eq(outside.area(), 0)
  let repeated = @moondeteval.CocoRle::from_polygons(4, 4, [
    [0.0, 0.0, 3.0, 0.0, 3.0, 0.0, 3.0, 3.0, 0.0, 3.0],
  ])
  assert_eq(repeated.to_compressed(), "0310004")
}

///|
test "polygon degenerate rings produce valid empty masks" {
  let point = @moondeteval.CocoRle::from_polygons(4, 4, [
    [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
  ])
  let line = @moondeteval.CocoRle::from_polygons(4, 4, [
    [1.0, 1.0, 3.0, 1.0, 2.0, 1.0],
  ])
  assert_eq(point.area(), 0)
  assert_eq(line.area(), 0)
  assert_eq(point.iou(line), 0.0)
}

///|
test "polygon parser rejects bad shape and accepts mixed segmentation forms" {
  let polygon = @moondeteval.parse_coco_segmentation(
    "[[0,0,3,0,3,3,0,3]]", 4, 4,
  )
  let rle = @moondeteval.parse_coco_segmentation(
    "{\"size\":[4,4],\"counts\":\"0310004\"}", 4, 4,
  )
  assert_eq(polygon.iou(rle), 1.0)
  for
    bad in [
      "[]", "[[]]", "[0,0,1,1,2,2]", "[[0,0,1,1,2]]", "[[0,0,1,1,\"x\",2]]", "null",
      "{\"size\":[2,8],\"counts\":[16]}",
    ] {
    assert_true(
      try @moondeteval.parse_coco_segmentation(bad, 4, 4) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
}

///|
test "polygon workload and non finite coordinate guards run before rasterization" {
  for value in [0.0 / 0.0, 1.0 / 0.0, 1.0e20] {
    assert_true(
      try
        @moondeteval.CocoRle::from_polygons(4, 4, [
          [value, 0.0, 2.0, 0.0, 2.0, 2.0],
        ])
      catch {
        error => error.message().contains("segmentation[0][0]")
      } noraise {
        _ => false
      },
    )
  }
  assert_true(
    try
      @moondeteval.CocoRle::from_polygons(4, 4, [
        [0.0, 0.0, 1000000.0, 0.0, 0.0, 1.0],
      ])
    catch {
      error => error.message().contains("boundary samples")
    } noraise {
      _ => false
    },
  )
  let too_many = Array::make(200002, 0.0)
  assert_true(
    try @moondeteval.CocoRle::from_polygons(1, 1, [too_many]) catch {
      error => error.message().contains("vertices")
    } noraise {
      _ => false
    },
  )
}

///|
test "polygon union cumulative workload is bounded" {
  let rings : Array[Array[Double]] = []
  for index in 0..<1600 {
    let x = (index * 2).to_double()
    rings.push([x, 0.0, x + 1.0, 0.0, x + 1.0, 1.0, x, 1.0])
  }
  assert_true(
    try @moondeteval.CocoRle::from_polygons(1, 3200, rings) catch {
      error => error.message().contains("union")
    } noraise {
      _ => false
    },
  )
}

///|
test "polygon sparse mask supports Int sized canvas without dense allocation" {
  let mask = @moondeteval.CocoRle::from_polygons(1, 2147483647, [
    [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0],
  ])
  assert_eq(mask.area(), 1)
  assert_eq(
    mask.iou(@moondeteval.CocoRle::new(1, 2147483647, [0, 1, 2147483646])),
    1.0,
  )
}

///|
test "polygon dataset and dataset aware predictions share declared image dimensions" {
  let source = "{\"images\":[{\"id\":5,\"width\":4,\"height\":4}],\"categories\":[{\"id\":7,\"name\":\"object\"}],\"annotations\":[{\"id\":9,\"image_id\":5,\"category_id\":7,\"area\":1024,\"segmentation\":[[0,0,3,0,3,3,0,3]]}]}"
  let dataset = @moondeteval.parse_coco_mask_dataset(source)
  assert_eq(dataset.truths()[0].mask().area(), 9)
  assert_eq(dataset.truths()[0].area(), 1024.0)
  let json = "[{\"image_id\":5,\"category_id\":7,\"score\":0.9,\"segmentation\":[[0,0,3,0,3,3,0,3]]}]"
  let predictions = @moondeteval.parse_coco_mask_detections_with_dataset(
    json, dataset,
  )
  let report = @moondeteval.evaluate_masks(dataset, predictions)
  assert_eq(report.summary().ap(), 1.0)
  assert_eq(report.summary().ap_medium(), 1.0)
  assert_true(
    try @moondeteval.parse_coco_mask_detections(json) catch {
      error => error.message().contains("with_dataset")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @moondeteval.parse_coco_mask_detections_with_dataset(
        json.replace(old="\"image_id\":5", new="\"image_id\":99"),
        dataset,
      )
    catch {
      error => error.message().contains("detections[0]")
    } noraise {
      _ => false
    },
  )
  assert_true(
    try
      @moondeteval.parse_coco_mask_dataset(
        source.replace(old="3,3,0,3", new="3,3,0"),
      )
    catch {
      error =>
        error.message().contains("annotations[0]") &&
        error.message().contains("segmentation[0]")
    } noraise {
      _ => false
    },
  )
}

///|
test "polygon fractional triangle matches reference encoding on every backend" {
  let mask = @moondeteval.CocoRle::from_polygons(7, 9, [
    [0.1, 0.9, 8.9, 1.1, 3.7, 6.3],
  ])
  assert_eq(mask.to_compressed(), "8251O2N00O1O1O1O0")
  assert_eq(mask.area(), 25)
}
