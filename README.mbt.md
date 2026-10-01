# MoonDetEval

MoonDetEval is a MoonBit library and native CLI for detector-independent, continuous-coordinate bounding-box evaluation. It is a separate October 2026 project from [MBMOT](https://github.com/python123-ops/mbmot), which measures multi-object tracking.

## Current scope

The library accepts validated in-memory images, categories, ground truths, and detections, or COCO-style JSON files. It computes the 12 standard COCO bbox summary metrics and per-category values. Scores are ranked in descending order; equal scores preserve input order. Crowd boxes use intersection over detection area and do not count as positive ground truths. Values of `-1` mean a metric has no eligible ground truths. Boxes use continuous `xywh` coordinates, without pixel-endpoint `+1` or automatic clipping.

The implementation is **under compatibility validation**. The [differential script](reference_compare.py) currently checks all 12 summary metrics against `pycocotools==2.0.7` on two synthetic fixtures, including crowd, duplicate predictions, sparse category IDs, area boundaries, and score ties. Broader cases, explicit ignore behavior, diagnostics, and configurable thresholds remain planned. Do not rely on full COCO equivalence yet.

## Run the example

```sh
moon run cli --target native -- examples/ground-truth.json examples/detections.json
```

The command prints a JSON report with `schema_version`, `summary`, and `classes`. The example's AP and AP50 are `1`, while AR@1 is `0`: the highest-scored prediction lands inside an ignored crowd box and occupies the single-detection slot. The second prediction matches the regular ground truth.

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
```

The public API also supports `Image::new`, `Category::new`, `Box::from_xywh`, `GroundTruth::new`, `Detection::new`, and `Dataset::new` for callers with records already in memory. Detection IDs must be unique per evaluation; the JSON adapter assigns zero-based IDs from source order. Coordinates and scores must be finite, and boxes must have positive dimensions. Image and category IDs may be sparse or zero. The CLI currently prints the report to standard output and returns a nonzero status for invalid input.

## Verify

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
python -m pip install pycocotools==2.0.7
python reference_compare.py
```

`pycocotools` is used only for development comparison; the MoonBit library does not depend on Python. The native CLI uses `moonbitlang/async@0.21.3` for file access.

## License and attribution

Apache-2.0. COCO's [official bbox evaluator](https://github.com/cocodataset/cocoapi/blob/master/PythonAPI/pycocotools/cocoeval.py) is a behavioral reference; its source code is not copied here. The example data is synthetic.
