"""Synthetic RLE mask AP + CLI checks against pycocotools==2.0.7.

Run: python examples/mask_ap_reference.py
Seed: 20261012. Absolute tolerance: 1e-9. No polygon rasterization.
"""
import contextlib
import copy
import importlib.metadata
import io
import json
import math
import random
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from pycocotools import mask as masks
from pycocotools.coco import COCO
from pycocotools.cocoeval import COCOeval

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from reference_compare import (METRICS, check_exported_curves, check_image_matches,
                               check_precision_recall)

SEED = 20261012
PREFIX = ["moon", "run", "cli", "--target", "native", "--"]


def encoded(value, height=None, width=None):
    if isinstance(value, list):
        assert height is not None and width is not None
        return masks.merge(masks.frPyObjects(value, height, width))
    if isinstance(value["counts"], list):
        return masks.frPyObjects(value, *value["size"])
    return {"size": value["size"], "counts": value["counts"].encode("ascii")}


def rle(height, width, counts, compressed=False):
    value = {"size": [height, width], "counts": counts}
    if compressed:
        value = encoded(value)
        value["counts"] = value["counts"].decode("ascii")
    return value


def gt(ident, image, category, segmentation, area=None, crowd=0, ignore=0):
    return {"id": ident, "image_id": image, "category_id": category,
            "segmentation": segmentation,
            "area": float(masks.area(encoded(segmentation))) if area is None else area,
            "iscrowd": crowd, "ignore": ignore}


def dt(image, category, segmentation, score=0.9):
    return {"image_id": image, "category_id": category,
            "segmentation": segmentation, "score": score}


def dataset(annotations, h=2, w=2, images=(1,), categories=(1,)):
    return {"images": [{"id": i, "height": h, "width": w} for i in images],
            "categories": [{"id": c, "name": str(c)} for c in categories],
            "annotations": annotations}


def reference(truth, predictions):
    truth = copy.deepcopy(truth)
    predictions = [copy.deepcopy(item) for item in predictions]
    canvases = {image["id"]: (image["height"], image["width"]) for image in truth["images"]}
    for item in truth["annotations"] + predictions:
        item["segmentation"] = encoded(item["segmentation"], *canvases[item["image_id"]])
    # loadRes prioritizes bbox; remove it for canonical mask pixel area.
    for item in predictions:
        item.pop("bbox", None)
        item.pop("area", None)
    coco = COCO()
    coco.dataset = truth
    coco.createIndex()
    if predictions:
        results = coco.loadRes(predictions)
    else:
        results = COCO()
        results.dataset = {"images": truth["images"], "categories": truth["categories"], "annotations": []}
        results.createIndex()
    evaluator = COCOeval(coco, results, "segm")
    evaluator.evaluate()
    evaluator.accumulate()
    evaluator.summarize()
    return evaluator


def category_metrics(evaluator, index):
    def ap(area=0, threshold=None):
        values = evaluator.eval["precision"][:, :, index, area, 2]
        if threshold is not None:
            values = values[np.isclose(evaluator.params.iouThrs, threshold)]
        valid = values[values > -1]
        return float(valid.mean()) if valid.size else -1.0

    def ar(area=0, maximum=2):
        values = evaluator.eval["recall"][:, index, area, maximum]
        valid = values[values > -1]
        return float(valid.mean()) if valid.size else -1.0

    return (ap(), ap(threshold=0.5), ap(threshold=0.75), ap(1), ap(2), ap(3),
            ar(maximum=0), ar(maximum=1), ar(), ar(1), ar(2), ar(3))


def assert_metrics(name, actual, expected):
    for metric, value in zip(METRICS, expected):
        assert math.isclose(actual[metric], float(value), rel_tol=0, abs_tol=1e-9), (
            name, metric, actual[metric], float(value))


def run_cli(truth, predictions, directory, *options):
    a, b = directory / "gt.json", directory / "dt.json"
    a.write_text(json.dumps(truth), encoding="utf-8")
    b.write_text(json.dumps(predictions), encoding="utf-8")
    return subprocess.run(PREFIX + [str(a), str(b), "--iou-type", "segm"] + list(options),
                          cwd=ROOT, text=True, encoding="utf-8", capture_output=True, timeout=60)


def compare(name, truth, predictions):
    with tempfile.TemporaryDirectory() as temporary:
        run = run_cli(truth, predictions, Path(temporary), "--diagnostics", "--image-ranking", "--pr-curves")
        assert run.returncode == 0, (name, run.stderr)
        report = json.loads(run.stdout)
    assert report["iou_type"] == "segm"
    assert report["config"]["ignore_policy"] == "coco_segm"
    assert report["quality_warnings"] == []
    with contextlib.redirect_stdout(io.StringIO()):
        evaluator = reference(truth, predictions)
    assert_metrics(name, report["summary"], evaluator.stats)
    by_category = {row["category_id"]: row["metrics"] for row in report["classes"]}
    for index, ident in enumerate(evaluator.params.catIds):
        assert_metrics((name, ident), by_category[ident], category_metrics(evaluator, index))
    check_exported_curves(name, report, evaluator)
    check_image_matches(name, report["diagnostics"], evaluator)
    check_precision_recall(name, report["diagnostics"], predictions, evaluator)
    expected = {image["id"]: [0, 0, 0, 0] for image in truth["images"]}
    for item in evaluator.evalImgs:
        if item is None or item["aRng"] != [0, 1e10]:
            continue
        matched, ignored = item["dtMatches"][0] != 0, item["dtIgnore"][0]
        missed = (item["gtMatches"][0] == 0) & ~item["gtIgnore"].astype(bool)
        row = expected[item["image_id"]]
        row[0] += int((matched & ~ignored).sum())
        row[1] += int((~matched & ~ignored).sum())
        row[2] += int(missed.sum())
        row[3] += int(ignored.sum())
    actual = {row["image_id"]: [row[k] for k in ("tp", "fp", "fn_count", "ignored")]
              for row in report["image_summaries"]}
    assert actual == expected, (name, actual, expected)
    print(name + ": summary/classes/PR/matches/images OK")
    return len(report["diagnostics"]), len(report["pr_curves"]) * 101


def fixtures():
    diagonal = rle(2, 2, [0, 1, 2, 1])
    opposite = rle(2, 2, [1, 2, 1], True)
    full, empty = rle(2, 2, [0, 4], True), rle(2, 2, [4])
    yield "perfect-mixed-rle", dataset([gt(1, 1, 1, diagonal)]), [dt(1, 1, diagonal)]
    yield "same-box-disjoint-pixels", dataset([gt(1, 1, 1, diagonal)]), [dict(dt(1, 1, opposite), bbox=[0, 0, 2, 2])]
    yield "no-detections", dataset([gt(1, 1, 1, diagonal)]), []
    yield "empty-masks", dataset([gt(1, 1, 1, empty)]), [dt(1, 1, empty)]
    yield "no-truths", dataset([]), [dt(1, 1, diagonal)]
    yield "empty-category", dataset([gt(1, 1, 1, diagonal)], categories=(7, 1)), [dt(1, 1, diagonal)]
    yield "crowd-repeat-and-priority", dataset([gt(1, 1, 1, full, crowd=1), gt(2, 1, 1, diagonal)]), [dt(1, 1, diagonal, score) for score in (0.9, 0.8, 0.7)]
    yield "crowd-only", dataset([gt(1, 1, 1, full, crowd=1)]), [dt(1, 1, diagonal), dt(1, 1, opposite)]
    yield "explicit-ignore-default", dataset([gt(1, 1, 1, diagonal, ignore=1)]), [dt(1, 1, diagonal)]
    yield "stable-cross-image-ties", dataset([gt(1, 2, 1, diagonal), gt(2, 1, 1, diagonal)], images=(2, 1)), [dt(2, 1, diagonal, 0.5), dt(1, 1, opposite, 0.5), dt(1, 1, diagonal, 0.5)]
    # COCO linspace uses 0.7000000000000001 here, while 7/10 is 0.7.
    # Diagnostic reconstruction must use that same recall grid.
    yield "recall-grid-seven-of-ten", dataset([gt(i, i, 1, diagonal) for i in range(1, 11)], images=range(1, 11)), [dt(i, 1, diagonal) for i in range(1, 8)]
    yield "rank-100-101", dataset([gt(1, 1, 1, diagonal)]), [dt(1, 1, empty, 0.5)] * 99 + [dt(1, 1, diagonal, 0.5)] * 2
    yield "rank-101-excluded", dataset([gt(1, 1, 1, diagonal)]), [dt(1, 1, empty, 0.5)] * 100 + [dt(1, 1, diagonal, 0.5)]
    yield "threshold-partial-overlap", dataset([gt(1, 1, 1, rle(1, 10, [0, 10]))], 1, 10), [dt(1, 1, rle(1, 10, [0, 6, 4], True))]
    small, wrong = rle(120, 120, [0, 1, 14399]), rle(120, 120, [1, 1, 14398], True)
    yield "pixel-area-not-box-or-supplied-area", dataset([gt(1, 1, 1, small)], 120, 120), [dict(dt(1, 1, wrong, 0.9), bbox=[0, 0, 120, 120], area=14400), dt(1, 1, small, 0.8)]
    yield "GT-area-shared-boundaries", dataset([gt(i, i, 1, small, area=a) for i, a in enumerate((0, 1023, 1024, 1025, 9215, 9216, 9217), 1)], 120, 120, range(1, 8)), [dt(i, 1, small) for i in range(1, 8)]
    for area in (1024, 1025, 9216, 9217):
        canvas = 15000
        gtmask, badmask = rle(1, canvas, [0, 1, canvas - 1]), rle(1, canvas, [1, area, canvas - area - 1], True)
        yield "unmatched-area-" + str(area), dataset([gt(1, 1, 1, gtmask, area=area)], 1, canvas), [dt(1, 1, badmask, 0.9), dt(1, 1, gtmask, 0.8)]


def random_mask(rng, height, width):
    pixels = np.zeros((height, width), dtype=np.uint8, order="F")
    for _ in range(rng.randrange(5)):
        x, y = rng.randrange(width), rng.randrange(height)
        pixels[y:rng.randrange(y + 1, height + 1), x:rng.randrange(x + 1, width + 1)] = 1
    result = masks.encode(pixels)
    if rng.randrange(2):
        result["counts"] = result["counts"].decode("ascii")
        return result
    # Pixel expansion is used only to construct small reference fixtures.
    runs, last, length = [], 0, 0
    for bit in pixels.flatten(order="F"):
        if int(bit) != last:
            runs.append(length)
            last, length = int(bit), 0
        length += 1
    runs.append(length)
    return rle(height, width, runs)


def random_fixtures():
    rng = random.Random(SEED)
    for case in range(24):
        height, width = ((7, 9), (1, 97), (120, 120))[case % 3]
        annotations, predictions = [], []
        for image in (5, 2, 9):
            for category in (7, 1):
                pool = []
                for _ in range(rng.randrange(4)):
                    value = random_mask(rng, height, width)
                    pool.append(value)
                    annotations.append(gt(len(annotations) + 1, image, category, value,
                                          crowd=int(rng.random() < 0.25), ignore=int(rng.random() < 0.2)))
                for _ in range(rng.randrange(7)):
                    value = copy.deepcopy(rng.choice(pool)) if pool and rng.random() < 0.6 else random_mask(rng, height, width)
                    predictions.append(dt(image, category, value, rng.choice((0.2, 0.5, 0.9))))
        rng.shuffle(predictions)
        yield "seeded-" + str(case), dataset(annotations, height, width, (5, 2, 9), (7, 1)), predictions


def check_cli():
    truth, wrong = rle(2, 2, [0, 1, 2, 1]), rle(2, 2, [1, 2, 1])
    data, bad = dataset([gt(1, 1, 1, truth)]), [dt(1, 1, wrong)]
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        candidate, output = directory / "candidate.json", directory / "paired.json"
        candidate.write_text(json.dumps([dt(1, 1, truth)]), encoding="utf-8")
        run = run_cli(data, bad, directory, "--compare", str(candidate), "--diagnostics", "--image-ranking", "--pr-curves", "--min-ap50", "1", "--output", str(output))
        assert run.returncode == 0, run.stderr
        report = json.loads(output.read_text(encoding="utf-8"))
        assert report["metrics"][0]["delta"] == 1
        assert report["image_changes"][0]["error_delta"] == -2
        assert report["baseline"]["iou_type"] == report["candidate"]["iou_type"] == "segm"
        assert report["candidate"]["pr_curves"][0]["precision"] == [1] * 101
        gate_output = directory / "gate.json"
        run = run_cli(data, bad, directory, "--min-ap50", "0.5", "--output", str(gate_output))
        assert run.returncode == 3 and gate_output.exists(), run.stderr
        saved = output.read_bytes()
        run = run_cli(data, bad, directory, "--output", str(output))
        assert run.returncode == 2 and output.read_bytes() == saved
        for options in (("--prediction-format", "yolo"), ("--iou-type", "segm"), ("--max-records", "1"), ("--max-report-bytes", "1"), ("--diagnostics", "--max-diagnostics", "1")):
            run = run_cli(data, bad, directory, *options)
            assert run.returncode == 2 and run.stdout == "", (options, run.stderr)
        invalid = [dict(bad[0], segmentation=[[0, 0, 2, 0, 2]]),
                   dict(bad[0], segmentation=rle(1, 4, [0, 4])),
                   dict(bad[0], image_id=99), dict(bad[0], category_id=99),
                   {k: v for k, v in bad[0].items() if k != "segmentation"}]
        for value in invalid:
            destination = directory / "invalid.json"
            run = run_cli(data, [value], directory, "--output", str(destination))
            assert run.returncode == 2 and not destination.exists(), (value, run.stderr)
            assert "detections[0]" in run.stderr, run.stderr
    print("segm paired/quality/output/limits/invalid-input native CLI: OK")


def main():
    assert importlib.metadata.version("pycocotools") == "2.0.7"
    counts = [0, 0, 0]
    for name, truth, predictions in list(fixtures()) + list(random_fixtures()):
        diagnostics, samples = compare(name, truth, predictions)
        counts[0] += 1
        counts[1] += diagnostics
        counts[2] += samples
    check_cli()
    print(json.dumps({"reference": "pycocotools==2.0.7", "seed": SEED, "tolerance": 1e-9,
                      "cases": counts[0], "diagnostic_entries": counts[1], "PR_samples": counts[2]}, sort_keys=True))


if __name__ == "__main__":
    main()
