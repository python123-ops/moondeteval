///|
test "sparse preparation retains only active image category groups in image order" {
  let images = Array::makei(1000, index => Image::new(index * 10 + 1, 4, 4))
  let box = Box::from_xywh(0.0, 0.0, 2.0, 2.0)
  let dataset = Dataset::new(
    images,
    [Category::new(-7, "a"), Category::new(85, "b")],
    [
      GroundTruth::new(1L, images[50].id, -7, box, area=4.0),
      GroundTruth::new(2L, images[50].id, 85, box, area=4.0),
    ],
  )
  let predictions = [
    { detection: Detection::new(1, images[25].id, 85, box, 0.5), order: 0, },
  ]
  let indexed = index_evaluation_inputs(dataset, predictions)
  let a = prepare_category(indexed, -7, 0)
  let b = prepare_category(indexed, 85, 0)
  assert_eq(a.length(), 1)
  assert_eq(b.length(), 2)
  assert_eq(b[0].image_id, images[25].id)
  assert_eq(b[1].image_id, images[50].id)
  assert_eq(b[1].all_truths.length(), 2)
  assert_eq(dataset.images().length(), 1000)
}

///|
test "overlap cache obeys per-category budget and falls back for an oversized image" {
  let mask = CocoRle::new(2, 2, [0, 1, 2, 1])
  let dataset = MaskDataset::new(
    [Image::new(1, 2, 2), Image::new(2, 2, 2)],
    [Category::new(1, "a")],
    [
      MaskGroundTruth::new(1L, 1, 1, mask, area=2.0),
      MaskGroundTruth::new(2L, 1, 1, mask, area=2.0, iscrowd=true),
      MaskGroundTruth::new(3L, 2, 1, mask, area=2.0),
      MaskGroundTruth::new(4L, 2, 1, mask, area=2.0),
    ],
  )
  let predictions : Array[RankedDetection] = []
  for image_id in [1, 2] {
    for offset in 0..<3 {
      let value = MaskDetection::new(
          image_id * 10 + offset,
          image_id,
          1,
          mask,
          0.9,
        ).value
      predictions.push({ detection: value, order: predictions.length(), })
    }
  }
  let indexed = index_evaluation_inputs(dataset.value, predictions)
  for (budget, expected) in [(0, 0), (5, 0), (6, 6), (7, 6), (12, 12)] {
    let prepared = prepare_category(indexed, 1, budget)
    let mut cached = 0
    for group in prepared {
      match group.overlaps {
        Some(rows) =>
          for row in rows {
            cached += row.length()
          }
        None => ()
      }
      for index in 0..<group.candidates.length() {
        for truth in group.truths {
          assert_eq(
            group.overlap(index, truth),
            instance_overlap(
              group.candidates[index].detection,
              truth.truth,
              truth.truth.iscrowd,
            ),
          )
        }
      }
    }
    assert_eq(cached, expected)
    assert_true(cached <= budget)
  }
}

///|
test "cached overlap rows stop at rank one hundred and columns survive truth reordering" {
  let mask = CocoRle::new(2, 2, [0, 1, 2, 1])
  let other = CocoRle::new(2, 2, [1, 2, 1])
  let dataset = MaskDataset::new(
    [Image::new(1, 2, 2)],
    [Category::new(1, "a")],
    [
      MaskGroundTruth::new(1L, 1, 1, mask, area=20000.0),
      MaskGroundTruth::new(2L, 1, 1, other, area=2.0),
    ],
  )
  let predictions = Array::makei(101, index => {
    detection: MaskDetection::new(index, 1, 1, mask, 0.5).value,
    order: index,
  })
  let prepared = prepare_category(
    index_evaluation_inputs(dataset.value, predictions),
    1,
    200,
  )
  let group = prepared[0]
  assert_eq(group.overlaps.unwrap().length(), 100)
  let reordered = [group.truths[1], group.truths[0]]
  assert_eq(group.overlap(0, reordered[0]), 0.0)
  assert_eq(group.overlap(0, reordered[1]), 1.0)
  assert_eq(group.overlap(100, reordered[1]), 1.0)
}
