///|
priv struct RankedTruth {
  truth : GroundTruth
  order : Int32
  cache_column : Int32
}

///|
priv struct PreparedImage {
  image_id : Int32
  truths : Array[RankedTruth]
  all_truths : Array[GroundTruth]
  candidates : Array[RankedDetection]
  overlaps : Array[Array[Double]]?
}

///|
priv struct IndexedCategory {
  truths : Map[Int32, Array[RankedTruth]]
  candidates : Map[Int32, Array[RankedDetection]]
}

///|
priv struct IndexedInputs {
  categories : Map[Int32, IndexedCategory]
  all_truths : Map[Int32, Array[GroundTruth]]
}

///|
/// Build category/image indexes once, retaining original input order for ties.
fn index_evaluation_inputs(
  dataset : Dataset,
  detections : Array[RankedDetection],
) -> IndexedInputs {
  let categories : Map[Int32, IndexedCategory] = Map([])
  let all_truths : Map[Int32, Array[GroundTruth]] = Map([])
  for category in dataset.categories {
    categories[category.id] = { truths: Map([]), candidates: Map([]), }
  }
  for order, truth in dataset.truths {
    match all_truths.get(truth.image_id) {
      Some(items) => items.push(truth)
      None => all_truths[truth.image_id] = [truth]
    }
    let group = categories[truth.category_id]
    match group.truths.get(truth.image_id) {
      Some(items) => items.push({ truth, order, cache_column: items.length(), })
      None =>
        group.truths[truth.image_id] = [{ truth, order, cache_column: 0, }]
    }
  }
  for candidate in detections {
    let detection = candidate.detection
    let group = categories[detection.category_id]
    match group.candidates.get(detection.image_id) {
      Some(items) => items.push(candidate)
      None => group.candidates[detection.image_id] = [candidate]
    }
  }
  { categories, all_truths, }
}

///|
/// Empty image/category groups contribute no records or positives to any curve.
/// Cache only complete top-100 DT/GT matrices that fit the remaining pair budget.
fn prepare_category(
  inputs : IndexedInputs,
  category_id : Int32,
  max_iou_cache_pairs : Int32,
) -> Array[PreparedImage] {
  let category = inputs.categories[category_id]
  let active : Map[Int32, Bool] = Map([])
  for image_id in category.truths.keys() {
    active[image_id] = true
  }
  for image_id in category.candidates.keys() {
    active[image_id] = true
  }
  let image_ids = active.keys().to_array()
  image_ids.sort()
  let mut remaining = max_iou_cache_pairs.to_int64()
  let prepared : Array[PreparedImage] = []
  for image_id in image_ids {
    let truths = category.truths.get(image_id).unwrap_or([])
    let candidates = category.candidates.get(image_id).unwrap_or([])
    candidates.sort_by(ranked_before)
    let count = candidates.length().min(100)
    let pairs = count.to_int64() * truths.length().to_int64()
    let overlaps = if pairs > 0L && pairs <= remaining {
      remaining -= pairs
      Some(
        Array::makei(count, fn(row) {
          Array::makei(truths.length(), fn(column) {
            let truth = truths[column].truth
            instance_overlap(candidates[row].detection, truth, truth.iscrowd)
          })
        }),
      )
    } else {
      None
    }
    prepared.push({
      image_id,
      truths,
      candidates,
      all_truths: inputs.all_truths.get(image_id).unwrap_or([]),
      overlaps,
    })
  }
  prepared
}

///|
fn PreparedImage::overlap(
  self : PreparedImage,
  detection_index : Int32,
  truth : RankedTruth,
) -> Double {
  match self.overlaps {
    Some(rows) if detection_index < rows.length() =>
      rows[detection_index][truth.cache_column]
    _ =>
      instance_overlap(
        self.candidates[detection_index].detection,
        truth.truth,
        truth.truth.iscrowd,
      )
  }
}

///|
fn validate_iou_cache_limit(limit : Int32) -> Unit raise EvalError {
  if limit < 0 || limit > 16777216 {
    raise InvalidConfig("max_iou_cache_pairs must be in [0,16777216]")
  }
}
