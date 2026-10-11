# Changelog

## Unreleased (source checkout)

- Evaluate COCO RLE instance-mask AP/AR: separate mask models and JSON adapters, 12 summary/per-class metrics, crowd and pixel-area handling, diagnostics, image summaries, PR curves and paired comparisons. Native CLI `--iou-type segm`, task-marked reports and viewer validation. Verify 43 fixed/seeded cases against `COCOeval(segm)`; polygons remain unsupported and the published `0.1.0` package is unchanged.

- Read/export COCO compressed mask RLE counts and parse standalone segmentation RLE JSON objects, with bounded decoding and malformed-input tests. Verify 35 mask pairs in three input forms and byte-for-byte exports against `pycocotools==2.0.7`.
- Add validated uncompressed COCO RLE mask area, ordinary IoU, and crowd overlap primitives; the initial 29 fixed/seeded cases match `pycocotools==2.0.7`.
- Native CLI `--help`/`-h` and early positional-argument diagnostics, with a real-process regression check; README entry-point guide and reproducible GitHub bug template.
- Local read-only browser viewer for single and paired JSON reports, including paged diagnostics and PR curves.
- Standard-library Python batch evaluator that runs multiple COCO predictors on one frozen ground-truth input and writes hashed, replayable reports with a comparable index.
- Multi-frame MBMOT example with explicit class mapping and overflow checks, stronger homography boundary tests, and independent three-package registry validation.

## 0.1.0 — initial release (2026-10-02)

- Reusable MoonBit API for continuous-coordinate COCO bbox evaluation: 12 summary metrics, per-class values, custom IoU thresholds, crowd/area/maxDets behavior, and structured input errors.
- COCO JSON and six-column YOLO prediction adapters, including multi-image YOLO manifests in the native CLI.
- Optional threshold-level match diagnostics, per-image error counts, 101-point precision/recall curves, paired detector comparison, and AP50/quality gates.
- Safe CLI output and configurable input, record, diagnostic, and report-size limits. These are not a process-memory cap.
- Validation on all four stable MoonBit backends, nine synthetic `pycocotools==2.0.7` differential cases, and an external 200-image COCO 2017 validation subset. Compatibility is limited to the tested bbox behavior.

Published at [Mooncakes](https://mooncakes.io/docs/python123-ops/moondeteval@0.1.0) from Git tag `v0.1.0` / commit `778bbd5`. A separate MoonBit module installed the exact registry version and ran the API; the registry-installed native CLI also passed the COCO/YOLO comparison fixture.
