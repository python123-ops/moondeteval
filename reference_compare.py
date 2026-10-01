"""Differential bbox metric check against pinned pycocotools 2.0.7.

Run from the repository root: python reference_compare.py
The reference package is development-only, not a MoonBit runtime dependency.
"""

import contextlib
import importlib.metadata
import io
import json
import math
import subprocess
import tempfile
from pathlib import Path

from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval


ROOT = Path(__file__).resolve().parent
METRICS = (
    "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large",
    "ar1", "ar10", "ar100", "ar_small", "ar_medium", "ar_large",
)


def compare(name, ground_truth, detections):
    with tempfile.TemporaryDirectory() as directory:
        gt_path = Path(directory) / "ground-truth.json"
        dt_path = Path(directory) / "detections.json"
        gt_path.write_text(json.dumps(ground_truth), encoding="utf-8")
        dt_path.write_text(json.dumps(detections), encoding="utf-8")
        run = subprocess.run(
            ["moon", "run", "cli", "--target", "native", "--", str(gt_path), str(dt_path)],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        actual = json.loads(run.stdout)["summary"]

    with contextlib.redirect_stdout(io.StringIO()):
        coco = COCO()
        coco.dataset = ground_truth
        coco.createIndex()
        evaluator = COCOeval(coco, coco.loadRes(detections), "bbox")
        evaluator.evaluate()
        evaluator.accumulate()
        evaluator.summarize()

    for metric, expected in zip(METRICS, evaluator.stats):
        if not math.isclose(actual[metric], float(expected), rel_tol=0, abs_tol=1e-9):
            raise AssertionError(
                f"{name}: {metric}: MoonDetEval={actual[metric]}, pycocotools={expected}"
            )
    print(f"{name}: all {len(METRICS)} summary metrics match (absolute tolerance 1e-9)")


def main():
    version = importlib.metadata.version("pycocotools")
    if version != "2.0.7":
        raise RuntimeError(f"expected pycocotools 2.0.7, found {version}")
    example_gt = json.loads((ROOT / "examples/ground-truth.json").read_text(encoding="utf-8"))
    example_dt = json.loads((ROOT / "examples/detections.json").read_text(encoding="utf-8"))
    compare("crowd and duplicate", example_gt, example_dt)

    gt = {
        "info": {},
        "images": [
            {"id": 2, "width": 200, "height": 200},
            {"id": 7, "width": 200, "height": 200},
        ],
        "categories": [{"id": 3, "name": "small"}, {"id": 9, "name": "large"}],
        "annotations": [
            {"id": 11, "image_id": 2, "category_id": 3, "bbox": [0, 0, 32, 32], "area": 1024, "iscrowd": 0},
            {"id": 12, "image_id": 7, "category_id": 3, "bbox": [50, 50, 40, 40], "area": 1600, "iscrowd": 0},
            {"id": 13, "image_id": 7, "category_id": 9, "bbox": [0, 0, 100, 100], "area": 10000, "iscrowd": 0},
        ],
    }
    dt = [
        {"image_id": 2, "category_id": 3, "bbox": [100, 100, 20, 20], "score": 0.9},
        {"image_id": 2, "category_id": 3, "bbox": [0, 0, 32, 32], "score": 0.9},
        {"image_id": 7, "category_id": 3, "bbox": [50, 50, 40, 40], "score": 0.8},
        {"image_id": 7, "category_id": 9, "bbox": [0, 0, 100, 100], "score": 0.7},
        {"image_id": 7, "category_id": 9, "bbox": [0, 0, 100, 100], "score": 0.6},
    ]
    compare("two images, sparse classes, area boundary, ties", gt, dt)


if __name__ == "__main__":
    main()
