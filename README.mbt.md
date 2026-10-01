# MoonDetEval

MoonDetEval is a MoonBit library and native CLI for detector-independent, continuous-coordinate bounding-box evaluation. It is a separate October 2026 project from [MBMOT](https://github.com/python123-ops/mbmot), which measures multi-object tracking.

## Current scope

The library accepts validated in-memory images, categories, ground truths, and detections, or COCO-style JSON files. It computes the 12 standard COCO bbox summary metrics and per-category values. Scores are ranked in descending order; equal scores preserve input order within an image/category, while cross-image accumulation follows sorted image IDs, matching the COCO reference. Crowd boxes use intersection over detection area and do not count as positive ground truths. Values of `-1` mean a metric has no eligible ground truths. Boxes use continuous `xywh` coordinates, without pixel-endpoint `+1` or automatic clipping.

The implementation is **under compatibility validation**. The [differential script](reference_compare.py) checks all 12 summary metrics, per-image matches, and 101-point precision/recall at all 10 default IoU thresholds against `pycocotools==2.0.7` on nine synthetic scenarios. These include explicit `ignore`, crowd, empty detections, `maxDets=100`, area and IoU boundaries, score ties within and across images, out-of-image boxes, and fixed-seed mixed images. This is stronger evidence for the covered bbox cases, but does not establish full COCO equivalence.

In the default `coco_bbox` mode, COCO bbox evaluation uses `iscrowd` to determine whether a ground truth is ignored, even when the source annotation contains `ignore=1`. The input flag remains available in the model. Callers who need that flag to affect matching can construct `EvalConfig::new(..., ignore_policy="respect_explicit")`; the chosen policy is recorded in the report. The latter is a MoonDetEval extension, not a COCO compatibility claim.

## Run the example

```sh
moon run cli --target native -- examples/ground-truth.json examples/detections.json
moon run cli --target native -- examples/ground-truth.json examples/detections.json --diagnostics --min-ap50 0.8
moon run cli --target native -- examples/ground-truth.json examples/detections.json --output report.json
python examples/compare_demo.py
```

The command prints a JSON report with `schema_version`, `evaluator_version`, `config`, `counts`, `summary`, `classes`, `diagnostics`, and `quality_warnings`. The example's AP and AP50 are `1`, while AR@1 is `0`: the highest-scored prediction lands inside an ignored crowd box and occupies the single-detection slot. The second prediction matches the regular ground truth. `counts` includes raw input totals and `evaluated_detections`, the predictions retained after the all-area maxDets=100 cap for each image/category. A retained prediction need not be a true positive. Warnings identify out-of-image ground-truth and detection boxes by source type and record/image/category IDs. They appear even without `--diagnostics`, and never clip boxes or alter AP/AR. `--diagnostics` includes decisions for each configured IoU threshold using the all-area range and maxDets=100. Each entry has source IDs, status (`tp`, `fp`, `ignored`, or `fn`), reason, and matched IoU (zero when unmatched). FP reasons use fixed priority: `duplicate`, `wrong_class`, `localization` (same-class IoU at least 0.1), then `background`. These explanations do not affect metrics.

For a direct two-detector comparison, run:

```sh
moon run cli --target native -- examples/compare-ground-truth.json examples/compare-baseline.json --compare examples/compare-candidate.json --diagnostics
```

`--compare` evaluates both prediction files against the same ground truths and configuration. The comparison JSON contains complete `baseline` and `candidate` reports, then 12 overall metric changes and 12 changes per class in stable metric order. Every `delta` is candidate minus baseline; a COCO `-1` undefined value becomes `null` in the comparison entries and its delta is `null`. The full nested reports still retain their original `-1` representation. In the included synthetic example, baseline AP50 is `1`, candidate AP50 is `0.25`, and the delta is `-0.75`; at IoU 0.5 candidate detection IDs 0, 1, and 3 are `wrong_class`, `localization`, and `duplicate`. `python examples/compare_demo.py` checks these values and prints a short readable trace. The diagnostic reason labels are MoonDetEval explanations, not official COCO categories.

`--min-ap50 N` accepts a finite value in `[0,1]` and checks the candidate in comparison mode. `--fail-on-warning` fails when any evaluated input has an out-of-image box. Either failed gate keeps the complete report and exits with code 3; invalid options or evaluation input exit with code 2. When both gates fail, the AP50 failure is reported first.

With `--output`, the CLI writes the JSON file and prints a one-line summary. It refuses to overwrite an existing path, creates an exclusive temporary file beside the target, syncs it, then renames it without replacement. A failed evaluation creates no report; a failed gate keeps the complete report. A pre-existing `.moondeteval.tmp` file is never deleted automatically. The default CLI limits are 64 MiB **per input file**, 100,000 total image/category/ground-truth/detection records across both models, an upper bound of 100,000 diagnostic entries across both reports, and 64 MiB of serialized report text. Use `--max-input-bytes`, `--max-records`, `--max-diagnostics`, and `--max-report-bytes` with positive integers to change them. These guard against accidental oversized work; they are not a hard process-memory limit.

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

The [independent consumer](https://github.com/python123-ops/moondeteval/blob/main/examples/consumer/consumer_test.mbt) is a separate MoonBit module linked to this checkout by its `moon.work` file. It checks the public API and includes a [small MBMOT detector adapter](https://github.com/python123-ops/moondeteval/blob/main/examples/consumer/mbmot_adapter.mbt): MBMOT detection boxes, scores, and class IDs become MoonDetEval predictions for a supplied image ID. Tracking IDs and MOT metrics are deliberately not involved. Run `moon test --target all --deny-warn` from `examples/consumer` to verify it. This is local workspace validation; installation of a published MoonDetEval version remains a separate release check.

## Verify

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
python examples/compare_demo.py
python -m pip install numpy==1.26.4 pycocotools==2.0.7
python reference_compare.py
```

`pycocotools` is used only for development comparison; the MoonBit library does not depend on Python. The native CLI uses `moonbitlang/async@0.21.3` for file access.

## License and attribution

Apache-2.0. COCO's [official bbox evaluator](https://github.com/cocodataset/cocoapi/blob/master/PythonAPI/pycocotools/cocoeval.py) is a behavioral reference; its source code is not copied here. The example data is synthetic.
