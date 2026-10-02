# MoonDetEval

MoonDetEval is a MoonBit library and native CLI for detector-independent, continuous-coordinate bounding-box evaluation. It is a separate October 2026 project from [MBMOT](https://github.com/python123-ops/mbmot), which measures multi-object tracking.

## Current scope

The library accepts validated in-memory images, categories, ground truths, and detections, or COCO-style JSON files. It computes the 12 standard COCO bbox summary metrics and per-category values. Scores are ranked in descending order; equal scores preserve input order within an image/category, while cross-image accumulation follows sorted image IDs, matching the COCO reference. Crowd boxes use intersection over detection area and do not count as positive ground truths. Values of `-1` mean a metric has no eligible ground truths. Boxes use continuous `xywh` coordinates, without pixel-endpoint `+1` or automatic clipping.

COCO annotation IDs use signed 64-bit integers because real validation annotations can exceed the 32-bit range. The parser accepts integer JSON numbers within that range, rejects fractional or out-of-range IDs, and preserves the exact ID in diagnostics. Report IDs remain JSON numbers. Library callers constructing `GroundTruth` directly now pass an `Int64` ID.

All 12 summary fields are unitless fractions in `[0,1]` when defined, in this order: `ap`, `ap50`, `ap75`, `ap_small`, `ap_medium`, `ap_large`, `ar1`, `ar10`, `ar100`, `ar_small`, `ar_medium`, `ar_large`. `ap` and `ar*` average over the configured IoU thresholds; `ap50` and `ap75` are fixed probes. Each field is `-1` when its category/area has no eligible ground truth, including a dataset with no categories or only crowd truths. In comparison `metrics` arrays use this same order; an undefined side and its `delta` are JSON `null`, while the nested single-model reports retain `-1`. Categories and per-class comparisons follow dataset category order, image summaries follow ascending image ID, and PR curves follow category order then configured ascending IoU threshold. Optional arrays are present but empty when disabled; enabling them does not change summary metrics. JSON object key order is not an API guarantee.

COCO JSON errors identify the source file (in CLI messages), record index, and decoded field path where available. Duplicate image/category/annotation IDs and unknown annotation references report their record and field. The underlying JSON parser resolves repeated keys within one object to the **last value** before model validation; duplicate object keys are not rejected. Producers should emit unique keys. A JSON number larger than JavaScript's exact integer range remains exact in MoonDetEval's annotation ID output, but a JavaScript consumer must use a lossless JSON parser to preserve it.

The implementation is **under compatibility validation**. The [differential script](https://github.com/python123-ops/moondeteval/blob/main/reference_compare.py) checks all 12 summary metrics, per-image matches, and exported 101-point precision/recall at all 10 default IoU thresholds against `pycocotools==2.0.7` on nine synthetic scenarios. These include explicit `ignore`, crowd, empty detections, `maxDets=100`, area and IoU boundaries, score ties within and across images, out-of-image boxes, and fixed-seed mixed images. This is stronger evidence for the covered bbox cases, but does not establish full COCO equivalence.

In the default `coco_bbox` mode, COCO bbox evaluation uses `iscrowd` to determine whether a ground truth is ignored, even when the source annotation contains `ignore=1`. The input flag remains available in the model. Callers who need that flag to affect matching can construct `EvalConfig::new(..., ignore_policy="respect_explicit")`; the chosen policy is recorded in the report. The latter is a MoonDetEval extension, not a COCO compatibility claim.

## Related packages

There is real feature overlap with [moonbit-visual-debug](https://mooncakes.io/docs/xlh123jjj/moonbit-visual-debug) and [moonbit-synthetic-vision](https://mooncakes.io/docs/caassien/moonbit-synthetic-vision). In the versions inspected on 2026-10-02 (`0.2.2` and `0.3.0`), the former exposes single-threshold detection precision/recall/F1, confusion data, and COCO/YOLO adapters; the latter exposes synthetic fixtures and integer-scale detection precision/recall. MoonDetEval focuses on the 12 COCO bbox AP/AR summaries, `maxDets`/crowd/area behavior checked against `pycocotools`, and a two-prediction native CLI with diagnostics and quality gates. This describes the inspected APIs, not a claim that no other package can evaluate detections.

## Install and call the library

Version [`0.1.0`](https://mooncakes.io/docs/python123-ops/moondeteval@0.1.0) is published on Mooncakes. Add the exact version to your own MoonBit module with `moon add python123-ops/moondeteval@0.1.0`, then add `"python123-ops/moondeteval"` to that package's `moon.pkg` imports. This minimal in-memory consumer was compiled and run both against the release archive and from a separate module using the exact registry version, producing `AP50=1`:

```moonbit nocheck
///|
fn main {
  let box = @moondeteval.Box::from_xywh(0.0, 0.0, 10.0, 10.0) catch {
    error => abort(error.message())
  }
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(1, 20, 20)],
    [@moondeteval.Category::new(7, "object")],
    [@moondeteval.GroundTruth::new(9L, 1, 7, box, area=100.0)],
  ) catch {
    error => abort(error.message())
  }
  let prediction = @moondeteval.Detection::new(0, 1, 7, box, 0.9) catch {
    error => abort(error.message())
  }
  let report = @moondeteval.evaluate(dataset, [prediction]) catch {
    error => abort(error.message())
  }
  println("AP50=\{report.summary().ap50()}")
}
```

## Run the source examples

From a checkout of this repository, run:

```sh
moon run cli --target native -- examples/ground-truth.json examples/detections.json
moon run cli --target native -- examples/ground-truth.json examples/detections.json --diagnostics --min-ap50 0.8
moon run cli --target native -- examples/ground-truth.json examples/detections.json --output report.json
python examples/compare_demo.py
python examples/showcase_demo.py
```

The first command's actual `schema_version` and `summary` fields are:

```json
{"schema_version":"0.1.0","summary":{"ap":1,"ap50":1,"ap75":1,"ap_small":1,"ap_medium":-1,"ap_large":-1,"ar1":0,"ar10":1,"ar100":1,"ar_small":1,"ar_medium":-1,"ar_large":-1}}
```

The command prints a JSON report with `schema_version`, `evaluator_version`, `config`, `counts`, `summary`, `classes`, `diagnostics`, and `quality_warnings`. The example's AP and AP50 are `1`, while AR@1 is `0`: the highest-scored prediction lands inside an ignored crowd box and occupies the single-detection slot. The second prediction matches the regular ground truth. `counts` includes raw input totals and `evaluated_detections`, the predictions retained after the all-area maxDets=100 cap for each image/category. A retained prediction need not be a true positive. Warnings identify out-of-image ground-truth and detection boxes by source type and record/image/category IDs. They appear even without `--diagnostics`, and never clip boxes or alter AP/AR. `--diagnostics` includes decisions for each configured IoU threshold using the all-area range and maxDets=100. Each entry has source IDs, status (`tp`, `fp`, `ignored`, or `fn`), reason, and matched IoU (zero when unmatched). FP reasons use fixed priority: `duplicate`, `wrong_class`, `localization` (same-class IoU at least 0.1), then `background`. These explanations do not affect metrics.

For a direct two-detector comparison, run:

```sh
moon run cli --target native -- examples/compare-ground-truth.json examples/compare-baseline.json --compare examples/compare-candidate.json --diagnostics
moon run cli --target native -- examples/compare-ground-truth.json examples/compare-baseline.json --compare examples/compare-candidate.json --image-ranking
moon run cli --target native -- examples/compare-ground-truth.json examples/compare-baseline.json --compare examples/compare-candidate.json --pr-curves
```

`--image-ranking` adds `image_summaries` to each evaluation: per image `tp`, `fp`, `fn_count`, and `ignored` at fixed IoU 0.50, all areas, and maxDets=100 per image/category. These are detection counts, not per-image AP. The option works without `--diagnostics` and does not alter AP/AR. In comparison mode, `image_changes` ranks images by `error_delta = candidate(fp + fn_count) - baseline(fp + fn_count)`, largest regression first, then image ID for ties. An image with no truths or predictions still has a zero-count row; crowd matches are `ignored`, not errors. The option is available to library callers through `EvalConfig::new(..., include_image_summaries=true)`. Without it the arrays are empty. This ranking is a review aid, not an official COCO metric.

`--pr-curves` adds a shared `recall_thresholds` grid (`0.00` to `1.00`, 101 values) and `pr_curves` entries for each category and configured IoU threshold, in dataset category order and ascending threshold order. Each curve contains `category_id`, `iou_threshold`, 101 sampled `precision` values, `max_recall`, and `ap`. It uses the same all-area, maxDets=100 precision envelope as AP; the mean of a defined curve's samples equals its `ap`. With no eligible ground truths, all 101 precision values, `max_recall`, and `ap` are `-1`; with eligible truths but no detections they are zero. A custom config exports only its configured IoU thresholds, even though AP50/AP75 remain fixed summary probes. Library callers use `EvalConfig::new(..., include_pr_curves=true)`. The option works without diagnostics or image ranking; in comparison mode each nested report carries its own curves. Without the option both arrays are empty. Existing `--max-report-bytes` also bounds the larger JSON output.

`--compare` evaluates both prediction files against the same ground truths and configuration. The comparison JSON contains complete `baseline` and `candidate` reports, then 12 overall metric changes and 12 changes per class in stable metric order. Every `delta` is candidate minus baseline; a COCO `-1` undefined value becomes `null` in the comparison entries and its delta is `null`. The full nested reports still retain their original `-1` representation. In the included synthetic example, baseline AP50 is `1`, candidate AP50 is `0.25`, and the delta is `-0.75`; at IoU 0.5 candidate detection IDs 0, 1, and 3 are `wrong_class`, `localization`, and `duplicate`. `python examples/compare_demo.py` checks these values and prints a short readable trace. The diagnostic reason labels are MoonDetEval explanations, not official COCO categories.

## Multi-image YOLO predictions

The native CLI can evaluate six-column YOLO prediction TXT files directly through a JSON manifest. The manifest's `category_ids` maps zero-based YOLO class indices to the ground-truth category IDs; each `images` entry names a ground-truth image ID and a TXT file relative to the manifest directory:

```json
{
  "category_ids": [42, 7],
  "images": [
    {"image_id": 12, "file": "labels/image-12.txt"},
    {"image_id": 9, "file": "labels/image-9.txt"}
  ]
}
```

These commands use the checked-in two-image fixture. The second command compares a COCO baseline against a YOLO candidate; the third deliberately fails its AP50 gate with exit code 3 while keeping the complete report in `failed-gate.json`.

```sh
moon run cli --target native -- examples/yolo/ground-truth.json examples/yolo/manifest.json --prediction-format yolo --diagnostics
moon run cli --target native -- examples/yolo/ground-truth.json examples/yolo/detections.json --compare examples/yolo/manifest.json --compare-format yolo --diagnostics
moon run cli --target native -- examples/yolo/ground-truth.json examples/yolo/manifest.json --prediction-format yolo --min-ap50 0.8 --output failed-gate.json
```

`--prediction-format` and `--compare-format` independently accept `coco` (default) or `yolo`; `--compare-format` requires `--compare`. A YOLO TXT row is `class_index center_x center_y width height confidence`. Class/coordinate/score validation is the same as `parse_yolo_detections`. Blank TXT files are valid, and an image absent from the manifest has zero predictions. Detection IDs start at zero and follow manifest order, then nonblank TXT row order. Duplicate image IDs or file names, unknown image/category IDs, invalid field types, and relative paths containing empty, `.` or `..` segments, backslashes or drive prefixes are rejected. A referenced file must exist and contain valid UTF-8; errors identify its path and, for malformed rows, the line. Path checks are lexical; the CLI operates on local files the caller supplies.

`python examples/yolo_manifest_demo.py` checks the 12 summary metrics, per-class results, diagnostics, and counts against equivalent COCO JSON, plus mixed-format zero deltas and failure behavior. This is a file-ingestion parity test, not an additional claim of COCO equivalence.

`--min-ap50 N` accepts a finite value in `[0,1]` and checks the candidate in comparison mode. `--fail-on-warning` fails when any evaluated input has an out-of-image box. Either failed gate keeps the complete report and exits with code 3; invalid options or evaluation input exit with code 2. When both gates fail, the AP50 failure is reported first.

With `--output`, the CLI writes the JSON file and prints a one-line summary. It refuses to overwrite an existing path, creates an exclusive temporary file beside the target, syncs it, then renames it without replacement. A failed evaluation creates no report; a failed gate keeps the complete report. A pre-existing `.moondeteval.tmp` file is never deleted automatically. The default CLI limits are 64 MiB **per input file** (including each YOLO TXT), 128 MiB total input bytes across ground truth, prediction files/manifests, and referenced TXT files, 100,000 total image/category/ground-truth/detection records across both models, an upper bound of 100,000 diagnostic entries across both reports, and 64 MiB of serialized report text. Use `--max-input-bytes`, `--max-total-input-bytes`, `--max-records`, `--max-diagnostics`, and `--max-report-bytes` with positive integers to change them. These guard against accidental oversized work; they are not a hard process-memory limit.

For performance measurements, build the native CLI with `moon build cli --target native --release` and add `--timings`. Successful runs print `input`, `evaluation`, `serialization`, and `output` durations in microseconds to stderr while leaving the JSON on stdout unchanged. `input` includes reading, parsing, and input validation; `output` includes report-size validation and writing to stdout or the requested file. The durations exclude process startup. In particular, `--max-report-bytes` is checked after serialization, so a large diagnostic report can consume substantial memory before the limit rejects it.

## Library use

```moonbit nocheck
///|
let dataset = @moondeteval.parse_coco_dataset(ground_truth_json)

///|
let predictions = @moondeteval.parse_coco_detections(detections_json)

///|
let report = @moondeteval.evaluate(dataset, predictions)

///|
let ap50 = report.summary().ap50()

///|
let config = @moondeteval.EvalConfig::new([0.5, 0.75], include_diagnostics=true)

///|
let custom = @moondeteval.evaluate_with_config(dataset, predictions, config)

///|
let comparison = @moondeteval.compare_predictions(
  dataset, predictions, other_predictions,
)

///|
let ap50_change = comparison.metrics()[1].delta()

///|
let yolo_predictions = @moondeteval.parse_yolo_detections(
  yolo_txt,
  dataset,
  9,
  [42, 7],
  first_detection_id=100,
)

///|
let manifest = @moondeteval.parse_yolo_manifest(manifest_json, dataset)

///|
let retained = report.counts().evaluated_detections()

///|
let warnings = report.quality_warnings()

///|
let explicit_ignore = @moondeteval.EvalConfig::new(
  [0.5],
  ignore_policy="respect_explicit",
)
```

The public API also supports `Image::new`, `Category::new`, `Box::from_xywh`, `GroundTruth::new`, `Detection::new`, and `Dataset::new` for callers with records already in memory. Detection IDs must be unique per evaluation; the JSON adapter assigns zero-based IDs from source order. Coordinates and scores must be finite, and boxes must have positive dimensions. Image and category IDs may be sparse or zero. Custom IoU thresholds must be strictly increasing in `(0,1]`; AP and AR average over them, while AP50 and AP75 remain fixed probes. Area bins and maxDets remain the COCO defaults. With no `--output`, the CLI prints JSON to standard output.

`parse_yolo_detections` accepts one image's six-column YOLO prediction TXT (`class_index center_x center_y width height confidence`). [Ultralytics `save_txt`](https://docs.ultralytics.com/reference/engine/results/#ultralytics.engine.results.Results.save_txt) omits confidence by default, so use `save_conf=True`; five-column training labels and seven-column tracking rows are intentionally rejected here because AP requires a score and tracking IDs are outside this adapter's scope. Pass the ground-truth `Dataset`, its image ID, and an explicit category map: `[42, 7]` maps YOLO class 0 to category 42 and class 1 to category 7. It uses that image's width and height to convert normalized center coordinates to continuous boxes, skips blank lines, and gives nonblank rows sequential IDs starting at `first_detection_id`. Use a nonoverlapping ID range when combining multiple image files. Class indices must be mapped, center/score fields must lie in `[0,1]`, and normalized width/height in `(0,1]`; errors identify the source line and field. A derived box that crosses the image edge is retained for evaluation and produces a quality warning. `parse_yolo_manifest` validates the ordered multi-image file list against a dataset; the native CLI then loads those files and assigns consecutive detection IDs.

The [independent consumer](https://github.com/python123-ops/moondeteval/blob/main/examples/consumer/consumer_test.mbt) is a separate MoonBit module linked to this checkout by its `moon.work` file. It checks the public API and includes a [small MBMOT detector adapter](https://github.com/python123-ops/moondeteval/blob/main/examples/consumer/mbmot_adapter.mbt): MBMOT detection boxes, scores, and class IDs become MoonDetEval predictions for a supplied image ID. Tracking IDs and MOT metrics are deliberately not involved. Run `moon test --target all --deny-warn` from `examples/consumer` to verify it. This is local workspace validation; installation of a published MoonDetEval version remains a separate release check.

The same consumer also imports the August [moon-cv-geometry](https://github.com/python123-ops/moon-cv-geometry) package at version `0.2.2`. Its [geometry adapter](https://github.com/python123-ops/moondeteval/blob/main/examples/consumer/geometry_adapter.mbt) converts a `Rect2` to a validated MoonDetEval `Box`, or maps four corners through a homography and evaluates the target-image envelope. The integration test gets AP50 `1` for a known transform and rejects a projective horizon crossing or zero-area rectangle. No geometry dependency is added to the MoonDetEval library; applications opt into the bridge when they need cross-view coordinates. The geometry repository's `examples/detection_bounds` independently shows the source side of the workflow.

## Verify a source checkout

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
python examples/compare_demo.py
python examples/yolo_manifest_demo.py
python -m pip install numpy==1.26.4 pycocotools==2.0.7
python reference_compare.py
```

`pycocotools` is used only for development comparison; the MoonBit library does not depend on Python. The native CLI uses `moonbitlang/async@0.21.3` for file access.

## License and attribution

MoonDetEval is Apache-2.0. COCO's [official bbox evaluator](https://github.com/cocodataset/cocoapi/blob/master/PythonAPI/pycocotools/cocoeval.py) is a behavioral reference; its source code is not copied here. The [COCO API license](https://github.com/cocodataset/cocoapi/blob/master/license.txt) is separate from this repository's license. `pycocotools==2.0.7` and NumPy are development-only reference tools, while the CLI's MoonBit runtime dependency is `moonbitlang/async@0.21.3`. The checked-in example data is synthetic. Real COCO images/annotations and YOLO model weights used for external validation are not bundled or redistributed in this repository.
