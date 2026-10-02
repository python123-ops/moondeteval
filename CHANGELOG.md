# Changelog

## 0.1.0 — initial release (2026-10-02)

- Reusable MoonBit API for continuous-coordinate COCO bbox evaluation: 12 summary metrics, per-class values, custom IoU thresholds, crowd/area/maxDets behavior, and structured input errors.
- COCO JSON and six-column YOLO prediction adapters, including multi-image YOLO manifests in the native CLI.
- Optional threshold-level match diagnostics, per-image error counts, 101-point precision/recall curves, paired detector comparison, and AP50/quality gates.
- Safe CLI output and configurable input, record, diagnostic, and report-size limits. These are not a process-memory cap.
- Validation on all four stable MoonBit backends, nine synthetic `pycocotools==2.0.7` differential cases, and an external 200-image COCO 2017 validation subset. Compatibility is limited to the tested bbox behavior.

Published at [Mooncakes](https://mooncakes.io/docs/python123-ops/moondeteval@0.1.0) from Git tag `v0.1.0` / commit `778bbd5`. A separate MoonBit module installed the exact registry version and ran the API; the registry-installed native CLI also passed the COCO/YOLO comparison fixture.
