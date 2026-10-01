# MoonDetEval

MoonDetEval is a MoonBit library for detector-independent bounding-box evaluation. It is being built for the October 2026 MoonBit hackathon as a separate project from [MBMOT](https://github.com/python123-ops/mbmot), which evaluates multi-object tracking.

## Current status

The repository currently provides a validated continuous-coordinate box type, COCO-style `xywh` conversion, and ordinary box IoU. Detection matching, AP/AR, COCO JSON input, diagnostics, and a CLI are planned work; no detection metric is claimed yet.

## Development

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all --deny-warn
```

The public library is designed to work across MoonBit's stable targets. No external runtime dependencies are required for the current core.

## Evaluation contract in progress

- Input: image and category IDs, ground-truth boxes, detection boxes, scores, and explicit evaluation configuration.
- Output: per-class AP/AR, aggregate metrics, and traceable per-detection diagnostics.
- Reference: [COCO bbox evaluator](https://github.com/cocodataset/cocoapi/blob/master/PythonAPI/pycocotools/cocoeval.py). The project will only claim full COCO compatibility after differential tests cover crowd/ignore, area ranges, and max detections.
- Scope: axis-aligned bounding boxes; no model inference, image decoding, segmentation, or tracking.

## License

Apache-2.0. All original MoonBit code in this repository is developed for MoonDetEval. COCO's evaluator is a behavioral reference; its source code is not copied here.
