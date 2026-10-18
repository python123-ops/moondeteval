# Changelog

## Unreleased (source checkout)

- Add shared MoonBit minimum-metric and baseline-drop gates for all 12 AP/AR metrics, including signed category scopes, explicit undefined handling and complete per-rule results. Expose them through the candidate CLI and batch evaluator; quality failures retain complete reports and return `3`. Extend optional report/batch fields and the read-only viewer without changing schema `0.1.0`, batch format `2` or legacy no-rule output. The bbox website demo now demonstrates an intentional AP50 regression failure.

- Add local batch-folder inspection to the report viewer: format-1 bbox and format-2 bbox/segm indexes, model summaries and switching, on-demand SHA-256 and report/index consistency checks, with missing-file and stale-load handling. Simplify the bilingual product site around installation, supported inputs and report examples.

- Prepare the `0.2.0` source candidate, with `evaluator_version=0.2.0` and unchanged report schema `0.1.0`; the Mooncakes `0.1.0` release and tag are unchanged. Add a bilingual static product site, CLI-generated bbox/mask/polygon demos, viewer deep links and browser checks. Candidate archive checks exercise mask APIs, the native CLI and batch segmentation independently of this checkout; exact registry checks accept a version parameter and still default to published `0.1.0`.

- Adopt MoonBit 0.10.15 formatter output for `Int32` annotations and optional-argument declarations in the library, CLI and consumer adapters; update consumer array JSON assertions to `Json(value)`. CI reports the installed toolchain version.

- Batch COCO mask evaluation with `--iou-type segm`, type-checked reports, format-2 indexes carrying task markers and replay flags, and preserved default bbox support for the published CLI. Seven batch checks pass; real YOLO11n-seg outputs on a 64-image COCO subset match the reference in three prediction configurations. Fix diagnostic PR reconstruction to use the reference recall grid rather than integer division; add a 7/10 recall boundary fixture and four-backend regression.

- Accept COCO polygon-ring segmentations in mask ground truths and dataset-aware predictions; rasterize and union to RLE in MoonBit with COCO boundary rules, finite-coordinate/work guards and indexed input errors. Preserve RLE-only APIs and route the segm CLI through the new parser. Check 178 pixel-exact geometry cases and 42 AP cases against `pycocotools==2.0.7`; retain adapted COCO BSD attribution in the package.

- Evaluate COCO RLE instance-mask AP/AR: separate mask models and JSON adapters, 12 summary/per-class metrics, crowd and pixel-area handling, diagnostics, image summaries, PR curves and paired comparisons. Native CLI `--iou-type segm`, task-marked reports and viewer validation. Verify 43 fixed/seeded cases against `COCOeval(segm)`; the published `0.1.0` package is unchanged.

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
