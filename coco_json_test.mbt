///|
test "COCO JSON parses into the in-memory evaluator" {
  let dataset = @moondeteval.parse_coco_dataset(
    "{\"images\":[{\"id\":1,\"width\":100,\"height\":100}],\"categories\":[{\"id\":4,\"name\":\"object\"}],\"annotations\":[{\"id\":9,\"image_id\":1,\"category_id\":4,\"bbox\":[0,0,20,20],\"area\":400}]}",
  )
  let predictions = @moondeteval.parse_coco_detections(
    "[{\"image_id\":1,\"category_id\":4,\"bbox\":[0,0,20,20],\"score\":0.9}]",
  )
  assert_eq(predictions[0].id(), 0)
  assert_true(
    @moondeteval.evaluate(dataset, predictions).summary().ap() > 0.999999,
  )
}

///|
test "COCO JSON accepts empty predictions and locates malformed boxes" {
  let predictions = @moondeteval.parse_coco_detections("[]")
  assert_eq(predictions.length(), 0)
  try
    @moondeteval.parse_coco_detections(
      "[{\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,1],\"score\":0.5}]",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("detections[0].bbox"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("short bbox accepted")
  }
}

///|
test "COCO JSON reports the record index for invalid field types" {
  try
    @moondeteval.parse_coco_detections(
      "[{\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,1,1],\"score\":0.5},{\"image_id\":\"bad\",\"category_id\":1,\"bbox\":[0,0,1,1],\"score\":0.5}]",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("detections[1]"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("invalid image id accepted")
  }
}

///|
test "COCO crowd annotation keeps a real-world 64-bit ground-truth id" {
  let dataset = @moondeteval.parse_coco_dataset(
    "{\"images\":[{\"id\":1,\"width\":100,\"height\":100}],\"categories\":[{\"id\":33,\"name\":\"suitcase\"}],\"annotations\":[{\"id\":903300451308,\"image_id\":1,\"category_id\":33,\"bbox\":[0,0,20,20],\"area\":400,\"iscrowd\":1},{\"id\":2,\"image_id\":1,\"category_id\":33,\"bbox\":[50,50,10,10],\"area\":100,\"iscrowd\":0}]}",
  )
  assert_eq(dataset.truths()[0].id(), 903300451308L)
  let predictions = @moondeteval.parse_coco_detections(
    "[{\"image_id\":1,\"category_id\":33,\"bbox\":[0,0,20,20],\"score\":0.9}]",
  )
  let report = @moondeteval.evaluate_with_diagnostics(dataset, predictions)
  assert_eq(report.diagnostics()[0].status(), "ignored")
  assert_eq(report.diagnostics()[0].ground_truth_id(), Some(903300451308L))
  assert_eq(report.diagnostics()[1].status(), "fn")
  assert_eq(report.diagnostics()[1].ground_truth_id(), Some(2L))
  assert_true(
    report.to_json_string().contains("\"ground_truth_id\":903300451308"),
  )
}

///|
test "COCO annotation IDs preserve integers beyond double precision" {
  let dataset = @moondeteval.parse_coco_dataset(
    "{\"images\":[{\"id\":1,\"width\":20,\"height\":20}],\"categories\":[{\"id\":1,\"name\":\"box\"}],\"annotations\":[{\"id\":9007199254740993,\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,10,10],\"area\":100}]}",
  )
  assert_eq(dataset.truths()[0].id(), 9007199254740993L)
  let report = @moondeteval.evaluate_with_diagnostics(dataset, [])
  assert_true(
    report.to_json_string().contains("\"ground_truth_id\":9007199254740993"),
  )
}

///|
test "COCO annotation IDs reject numbers outside signed 64-bit range" {
  try
    @moondeteval.parse_coco_dataset(
      "{\"images\":[{\"id\":1,\"width\":20,\"height\":20}],\"categories\":[{\"id\":1,\"name\":\"box\"}],\"annotations\":[{\"id\":9223372036854775808,\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,10,10],\"area\":100}]}",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("annotations[0].id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("out-of-range annotation id accepted")
  }
}

///|
test "COCO JSON errors locate typed fields and duplicate or unknown references" {
  let prefix = "{\"images\":[{\"id\":1,\"width\":20,\"height\":20}],\"categories\":[{\"id\":2,\"name\":\"box\"}],\"annotations\":["
  let suffix = "]}"
  let valid = "{\"id\":1,\"image_id\":1,\"category_id\":2,\"bbox\":[0,0,10,10],\"area\":100}"
  let bad_image = "{\"id\":2,\"image_id\":9,\"category_id\":2,\"bbox\":[0,0,10,10],\"area\":100}"
  try
    @moondeteval.parse_coco_dataset(prefix + valid + "," + bad_image + suffix)
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("annotations[1].image_id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("unknown image accepted")
  }
  try
    @moondeteval.parse_coco_dataset(prefix + valid + "," + valid + suffix)
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("annotations[1].id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate truth accepted")
  }
  try
    @moondeteval.parse_coco_detections(
      "[{\"image_id\":1,\"category_id\":2,\"bbox\":[0,0,10,10],\"score\":\"bad\"}]",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(
        message.contains("detections[0]") && message.contains("score"),
      )
    _ => fail("wrong error")
  } noraise {
    _ => fail("invalid score accepted")
  }
  try
    @moondeteval.parse_coco_dataset(
      prefix +
      "{\"id\":1.5,\"image_id\":1,\"category_id\":2,\"bbox\":[0,0,10,10],\"area\":100}" +
      suffix,
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("annotations[0].id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("fractional truth ID accepted")
  }
}

///|
test "COCO JSON rejects invalid crowd and ignore flags and truncated input" {
  let prefix = "{\"images\":[{\"id\":1,\"width\":20,\"height\":20}],\"categories\":[{\"id\":2,\"name\":\"box\"}],\"annotations\":[{\"id\":1,\"image_id\":1,\"category_id\":2,\"bbox\":[0,0,10,10],\"area\":100,"
  for (field, value) in [("iscrowd", "2"), ("ignore", "\"yes\"")] {
    try
      @moondeteval.parse_coco_dataset(
        prefix + "\"" + field + "\":" + value + "}]}",
      )
    catch {
      @moondeteval.InvalidInput(message) =>
        assert_true(message.contains("annotations[0]." + field))
      _ => fail("wrong error")
    } noraise {
      _ => fail("invalid flag accepted")
    }
  }
  try @moondeteval.parse_coco_dataset("{\"images\":[") catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("not valid JSON"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("truncated input accepted")
  }
}

///|
test "COCO annotation IDs keep both signed 64-bit endpoints" {
  let dataset = @moondeteval.parse_coco_dataset(
    "{\"images\":[{\"id\":1,\"width\":20,\"height\":20}],\"categories\":[{\"id\":1,\"name\":\"box\"}],\"annotations\":[{\"id\":-9223372036854775808,\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,10,10],\"area\":100},{\"id\":9223372036854775807,\"image_id\":1,\"category_id\":1,\"bbox\":[0,0,10,10],\"area\":100}]}",
  )
  assert_eq(dataset.truths()[0].id().to_string(), "-9223372036854775808")
  assert_eq(dataset.truths()[1].id().to_string(), "9223372036854775807")
  let report = @moondeteval.evaluate_with_diagnostics(dataset, [])
  assert_true(
    report.to_json_string().contains("\"ground_truth_id\":-9223372036854775808"),
  )
  assert_true(
    report.to_json_string().contains("\"ground_truth_id\":9223372036854775807"),
  )
}

///|
test "COCO JSON locates missing prediction fields and duplicate declarations" {
  try
    @moondeteval.parse_coco_detections(
      "[{\"image_id\":1,\"category_id\":2,\"bbox\":[0,0,1,1]}]",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(
        message.contains("detections[0]") && message.contains("score"),
      )
    _ => fail("wrong error")
  } noraise {
    _ => fail("missing score accepted")
  }
  try
    @moondeteval.parse_coco_dataset(
      "{\"images\":[{\"id\":1,\"width\":20,\"height\":20},{\"id\":1,\"width\":20,\"height\":20}],\"categories\":[],\"annotations\":[]}",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("images[1].id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate image accepted")
  }
  try
    @moondeteval.parse_coco_dataset(
      "{\"images\":[],\"categories\":[{\"id\":1,\"name\":\"box\"},{\"id\":1,\"name\":\"box\"}],\"annotations\":[]}",
    )
  catch {
    @moondeteval.InvalidInput(message) =>
      assert_true(message.contains("categories[1].id"))
    _ => fail("wrong error")
  } noraise {
    _ => fail("duplicate category accepted")
  }
}
