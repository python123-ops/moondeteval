"""Differential bbox metric check against pinned pycocotools 2.0.7.

Run from the repository root: python reference_compare.py
The reference package is development-only, not a MoonBit runtime dependency.
"""

import contextlib
import importlib.metadata
import io
import json
import math
import random
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


def compare(name, ground_truth, detections, check_matches=True):
    with tempfile.TemporaryDirectory() as directory:
        gt_path = Path(directory) / "ground-truth.json"
        dt_path = Path(directory) / "detections.json"
        gt_path.write_text(json.dumps(ground_truth), encoding="utf-8")
        dt_path.write_text(json.dumps(detections), encoding="utf-8")
        run = subprocess.run(
            ["moon", "run", "cli", "--target", "native", "--", str(gt_path), str(dt_path)]
            + (["--diagnostics"] if check_matches else []) + ["--pr-curves"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        report = json.loads(run.stdout)
        actual = report["summary"]

    with contextlib.redirect_stdout(io.StringIO()):
        coco = COCO()
        coco.dataset = ground_truth
        coco.createIndex()
        if detections:
            results = coco.loadRes(detections)
        else:
            results = COCO()
            results.dataset = {
                "images": ground_truth["images"],
                "categories": ground_truth["categories"],
                "annotations": [],
            }
            results.createIndex()
        evaluator = COCOeval(coco, results, "bbox")
        evaluator.evaluate()
        evaluator.accumulate()
        evaluator.summarize()

    for metric, expected in zip(METRICS, evaluator.stats):
        if not math.isclose(actual[metric], float(expected), rel_tol=0, abs_tol=1e-9):
            raise AssertionError(
                f"{name}: {metric}: MoonDetEval={actual[metric]}, pycocotools={expected}"
            )
    check_exported_curves(name, report, evaluator)
    if check_matches:
        check_image_matches(name, report["diagnostics"], evaluator)
        check_precision_recall(name, report["diagnostics"], detections, evaluator)
    print(f"{name}: {len(METRICS)} metrics and exported PR curves match (absolute tolerance 1e-9)")


def check_exported_curves(name, report, evaluator):
    grid = report["recall_thresholds"]
    assert len(grid) == 101, (name, len(grid))
    for index, (actual, expected) in enumerate(zip(grid, evaluator.params.recThrs)):
        assert math.isclose(actual, float(expected), abs_tol=1e-12), (
            name, "recall grid", index, actual, expected
        )
    curves = report["pr_curves"]
    assert len(curves) == len(evaluator.params.catIds) * len(evaluator.params.iouThrs)
    by_key = {(curve["category_id"], round(curve["iou_threshold"], 2)): curve
              for curve in curves}
    assert len(by_key) == len(curves), name
    for category_index, category_id in enumerate(evaluator.params.catIds):
        for threshold_index, threshold in enumerate(evaluator.params.iouThrs):
            curve = by_key[(category_id, round(float(threshold), 2))]
            expected_precision = evaluator.eval["precision"][
                threshold_index, :, category_index, 0, 2
            ]
            expected_recall = evaluator.eval["recall"][
                threshold_index, category_index, 0, 2
            ]
            assert len(curve["precision"]) == 101
            for sample, (actual, expected) in enumerate(
                zip(curve["precision"], expected_precision)
            ):
                assert math.isclose(actual, float(expected), abs_tol=1e-9), (
                    name, category_id, threshold, sample, actual, expected
                )
            assert math.isclose(curve["max_recall"], float(expected_recall), abs_tol=1e-9)
            expected_ap = (-1.0 if expected_precision[0] < 0
                           else float(expected_precision.mean()))
            assert math.isclose(curve["ap"], expected_ap, abs_tol=1e-9), (
                name, category_id, threshold, curve["ap"], expected_ap
            )


def check_image_matches(name, diagnostics, evaluator):
    by_key = {
        (item["category_id"], item["image_id"], round(item["iou_threshold"], 2),
         item.get("detection_id")): item
        for item in diagnostics
    }
    for image_eval in evaluator.evalImgs:
        if image_eval is None or image_eval["aRng"] != [0, 10000000000.0]:
            continue
        category_id = image_eval["category_id"]
        image_id = image_eval["image_id"]
        for threshold_index, threshold in enumerate(evaluator.params.iouThrs):
            threshold_key = round(float(threshold), 2)
            for offset, detection_id in enumerate(image_eval["dtIds"]):
                key = (category_id, image_id, threshold_key, detection_id - 1)
                item = by_key[key]
                expected_gt = int(image_eval["dtMatches"][threshold_index, offset])
                expected_ignore = bool(image_eval["dtIgnore"][threshold_index, offset])
                assert item.get("ground_truth_id") == (expected_gt or None), (name, key, item)
                assert (item["status"] == "ignored") == expected_ignore, (name, key, item)
                assert (item["status"] == "tp") == (expected_gt != 0 and not expected_ignore)
            missed = {
                ground_truth_id
                for offset, ground_truth_id in enumerate(image_eval["gtIds"])
                if not image_eval["gtIgnore"][offset]
                and image_eval["gtMatches"][threshold_index, offset] == 0
            }
            actual_missed = {
                item["ground_truth_id"]
                for item in diagnostics
                if round(item["iou_threshold"], 2) == threshold_key
                and item["category_id"] == category_id
                and item["image_id"] == image_id
                and item["status"] == "fn"
            }
            assert actual_missed == missed, (name, category_id, image_id, threshold_key, actual_missed, missed)


def check_precision_recall(name, diagnostics, detections, evaluator):
    for category_index, category_id in enumerate(evaluator.params.catIds):
        positives = sum(
            sum(not ignored for ignored in image_eval["gtIgnore"])
            for image_eval in evaluator.evalImgs
            if image_eval is not None
            and image_eval["aRng"] == [0, 10000000000.0]
            and image_eval["category_id"] == category_id
        )
        for threshold_index, threshold in enumerate(evaluator.params.iouThrs):
            threshold_key = round(float(threshold), 2)
            records = [
                item for item in diagnostics
                if item["category_id"] == category_id
                and round(item["iou_threshold"], 2) == threshold_key
                and item.get("detection_id") is not None
            ]
            records.sort(key=lambda item: (
                -detections[item["detection_id"]]["score"],
                item["image_id"], item["detection_id"]
            ))
            if positives == 0:
                sampled = [-1.0] * 101
                max_recall = -1.0
            else:
                tp = fp = 0
                precision = []
                recall = []
                for item in records:
                    if item["status"] == "ignored":
                        continue
                    tp += item["status"] == "tp"
                    fp += item["status"] == "fp"
                    precision.append(tp / (tp + fp))
                    recall.append(tp / positives)
                max_recall = recall[-1] if recall else 0.0
                for index in range(len(precision) - 2, -1, -1):
                    precision[index] = max(precision[index], precision[index + 1])
                sampled = [
                    next((precision[index] for index, value in enumerate(recall)
                          if value >= sample / 100), 0.0)
                    for sample in range(101)
                ]
            expected_precision = evaluator.eval["precision"][
                threshold_index, :, category_index, 0, 2
            ]
            expected_recall = evaluator.eval["recall"][
                threshold_index, category_index, 0, 2
            ]
            for sample, (actual, expected) in enumerate(zip(sampled, expected_precision)):
                assert math.isclose(actual, float(expected), abs_tol=1e-9), (
                    name, category_id, threshold_key, sample, actual, expected
                )
            assert math.isclose(max_recall, float(expected_recall), abs_tol=1e-9), (
                name, category_id, threshold_key, max_recall, expected_recall
            )


def check_cli_options():
    gt_path = ROOT / "examples/ground-truth.json"
    dt_path = ROOT / "examples/detections.json"
    command = ["moon", "run", "cli", "--target", "native", "--", str(gt_path), str(dt_path)]
    plain = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
    traced = subprocess.run(
        command + ["--diagnostics", "--min-ap50", "1"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    plain_report = json.loads(plain.stdout)
    traced_report = json.loads(traced.stdout)
    assert plain_report["summary"] == traced_report["summary"]
    assert plain_report["diagnostics"] == []
    assert len(traced_report["diagnostics"]) == 30
    assert [item["status"] for item in traced_report["diagnostics"][:3]] == [
        "ignored", "tp", "fp"
    ]

    with tempfile.TemporaryDirectory() as directory:
        directory = Path(directory)
        report_path = directory / "report.json"
        saved = subprocess.run(
            command + ["--output", str(report_path)],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert saved.returncode == 0, saved.stderr
        assert saved.stdout.startswith("AP=")
        assert json.loads(report_path.read_text(encoding="utf-8"))["summary"] == plain_report["summary"]
        original_bytes = report_path.read_bytes()
        existing = subprocess.run(
            command + ["--output", str(report_path)],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert existing.returncode == 2
        assert report_path.read_bytes() == original_bytes
        assert not Path(str(report_path) + ".moondeteval.tmp").exists()

        for option in (["--max-input-bytes", "1"], ["--max-records", "1"],
                       ["--max-report-bytes", "1"],
                       ["--diagnostics", "--max-diagnostics", "1"]):
            limited_path = directory / "limited.json"
            limited = subprocess.run(
                command + ["--output", str(limited_path)] + option,
                cwd=ROOT, capture_output=True, text=True,
            )
            assert limited.returncode == 2, limited.stderr
            assert not limited_path.exists()
            assert not Path(str(limited_path) + ".moondeteval.tmp").exists()

        bad_input = directory / "bad.json"
        bad_input.write_text("{", encoding="utf-8")
        bad_output = directory / "bad-output.json"
        bad = subprocess.run(
            command[:-1] + [str(bad_input), "--output", str(bad_output)],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert bad.returncode == 2
        assert not bad_output.exists()
        assert not Path(str(bad_output) + ".moondeteval.tmp").exists()

        missing = subprocess.run(
            command[:-1] + [str(directory / "missing.json")],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert missing.returncode == 2
        assert "cannot inspect input" in missing.stderr

        empty_path = Path(directory) / "empty.json"
        empty_path.write_text("[]", encoding="utf-8")
        failed = subprocess.run(
            command[:-1] + [str(empty_path), "--min-ap50", "0.5", "--output", str(directory / "gate.json")],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert failed.returncode == 3, failed.stderr
        assert json.loads((directory / "gate.json").read_text(encoding="utf-8"))["summary"]["ap50"] == 0
        assert "AP50 gate failed" in failed.stderr

        stale = directory / "stale.json.moondeteval.tmp"
        stale.write_text("keep", encoding="utf-8")
        collision = subprocess.run(
            command + ["--output", str(directory / "stale.json")],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert collision.returncode == 2
        assert stale.read_text(encoding="utf-8") == "keep"

    invalid = subprocess.run(
        command + ["--min-ap50", "nan"],
        cwd=ROOT, capture_output=True, text=True,
    )
    assert invalid.returncode == 2
    assert not invalid.stdout
    print("CLI diagnostics, AP50 gate, input limits, and safe file output verified")


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

    boundary_gt = {
        "info": {},
        "images": [{"id": 1, "width": 100, "height": 100}],
        "categories": [{"id": 1, "name": "object"}],
        "annotations": [
            {"id": 1, "image_id": 1, "category_id": 1, "bbox": [0, 0, 20, 10], "area": 200, "iscrowd": 0}
        ],
    }
    boundary_dt = [
        {"image_id": 1, "category_id": 1, "bbox": [0, 0, 17, 10], "score": 0.9}
    ]
    compare("IoU exactly at the 0.85 threshold", boundary_gt, boundary_dt)

    explicit_ignore_gt = {
        "info": {},
        "images": [{"id": 1, "width": 20, "height": 20}],
        "categories": [{"id": 1, "name": "object"}],
        "annotations": [
            {"id": 1, "image_id": 1, "category_id": 1, "bbox": [0, 0, 10, 10],
             "area": 100, "iscrowd": 0, "ignore": 1}
        ],
    }
    explicit_ignore_dt = [
        {"image_id": 1, "category_id": 1, "bbox": [0, 0, 10, 10], "score": 0.9}
    ]
    compare("bbox explicit ignore is overridden by iscrowd", explicit_ignore_gt, explicit_ignore_dt)

    compare("empty detections", explicit_ignore_gt, [])

    capped_gt = {
        "info": {},
        "images": [{"id": 1, "width": 300, "height": 300}],
        "categories": [{"id": 1, "name": "object"}],
        "annotations": [
            {"id": 1, "image_id": 1, "category_id": 1, "bbox": [0, 0, 20, 20],
             "area": 400, "iscrowd": 0}
        ],
    }
    capped_dt = [
        {"image_id": 1, "category_id": 1, "bbox": [100, 100, 10, 10],
         "score": 1 - index / 1000}
        for index in range(100)
    ] + [{"image_id": 1, "category_id": 1, "bbox": [0, 0, 20, 20], "score": 0.1}]
    compare("maxDets excludes rank 101", capped_gt, capped_dt)

    area_gt = {
        "info": {},
        "images": [{"id": 1, "width": 120, "height": 120}],
        "categories": [{"id": 1, "name": "object"}],
        "annotations": [
            {"id": 1, "image_id": 1, "category_id": 1, "bbox": [0, 0, 96, 96],
             "area": 9216, "iscrowd": 0}
        ],
    }
    area_dt = [
        {"image_id": 1, "category_id": 1, "bbox": [-5, -5, 96, 96], "score": 0.9},
        {"image_id": 1, "category_id": 1, "bbox": [0, 0, 96, 96], "score": 0.8},
    ]
    compare("area 9216 and out-of-image box", area_gt, area_dt)

    rng = random.Random(20261001)
    random_gt = {
        "info": {},
        "images": [{"id": 2, "width": 100, "height": 100},
                   {"id": 5, "width": 100, "height": 100}],
        "categories": [{"id": 1, "name": "one"}, {"id": 9, "name": "nine"}],
        "annotations": [],
    }
    random_dt = []
    for index in range(12):
        image_id = rng.choice([2, 5])
        category_id = rng.choice([1, 9])
        x, y = rng.randrange(-5, 85), rng.randrange(-5, 85)
        width, height = rng.randrange(10, 31), rng.randrange(10, 31)
        bbox = [x, y, width, height]
        if index < 6:
            random_gt["annotations"].append({
                "id": index + 1, "image_id": image_id, "category_id": category_id,
                "bbox": bbox, "area": width * height, "iscrowd": 0,
            })
        random_dt.append({
            "image_id": image_id, "category_id": category_id,
            "bbox": bbox if index % 3 == 0 else
                    [x + rng.randrange(-8, 9), y + rng.randrange(-8, 9), width, height],
            "score": round(rng.random(), 1),
        })
    compare("fixed-seed mixed images and classes", random_gt, random_dt)

    cross_image_ties_gt = {
        "info": {},
        "images": [{"id": 2, "width": 100, "height": 100},
                   {"id": 1, "width": 100, "height": 100}],
        "categories": [{"id": 1, "name": "object"}],
        "annotations": [
            {"id": 1, "image_id": 1, "category_id": 1,
             "bbox": [0, 0, 10, 10], "area": 100, "iscrowd": 0},
            {"id": 2, "image_id": 2, "category_id": 1,
             "bbox": [0, 0, 10, 10], "area": 100, "iscrowd": 0},
        ],
    }
    cross_image_ties_dt = [
        {"image_id": 2, "category_id": 1, "bbox": [0, 0, 10, 10], "score": 0.9},
        {"image_id": 1, "category_id": 1, "bbox": [50, 50, 10, 10], "score": 0.9},
        {"image_id": 1, "category_id": 1, "bbox": [0, 0, 10, 10], "score": 0.8},
    ]
    compare("equal scores across images", cross_image_ties_gt, cross_image_ties_dt)
    check_cli_options()


if __name__ == "__main__":
    main()
