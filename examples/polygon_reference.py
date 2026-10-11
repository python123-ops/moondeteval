"""COCO polygon rasterization and mask AP differential checks.

Run: python examples/polygon_reference.py (pycocotools==2.0.7).
Synthetic fixtures only; seed 20261013, pixel equality and metric tolerance 1e-9.
"""
import copy
import importlib.metadata
import json
import math
import random
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from pycocotools import mask as masks

import mask_ap_reference as evaluation

SEED = 20261013


def reference_mask(polygons, height, width):
    return masks.merge(masks.frPyObjects(polygons, height, width))


def json_rle(mask):
    return {"size": mask["size"], "counts": mask["counts"].decode("ascii")}


def rect(x, y, width, height):
    return [x, y, x + width, y, x + width, y + height, x, y + height]


def fixtures():
    fixed = [
        (4, 4, [rect(0, 0, 3, 3)]),
        (4, 4, [rect(-2, -2, 8, 8)]),
        (4, 4, [rect(-4, -4, 2, 2)]),
        (4, 4, [rect(4, 0, 2, 4)]),
        (4, 4, [rect(0, 4, 4, 2)]),
        (4, 4, [rect(0.5, 0.5, 2, 2)]),
        (4, 4, [rect(-0.3, -0.3, 2, 2)]),
        (4, 4, [rect(0, 0, 4, 4), rect(1, 1, 2, 2)[::-1]]),
        (4, 4, [rect(0, 0, 2, 2), rect(1, 1, 2, 2)]),
        (4, 4, [rect(0, 0, 1, 1), rect(3, 3, 1, 1)]),
        (4, 4, [[0, 0, 3, 0, 3, 0, 3, 3, 0, 3]]),
        (4, 4, [[0, 0, 3, 0, 3, 3, 0, 3, 0, 0]]),
        (4, 4, [[1, 1, 1, 1, 1, 1]]),
        (4, 4, [[1, 1, 3, 1, 2, 1]]),
        (4, 4, [[0, 0, 3, 3, 0, 3, 3, 0]]),
        (7, 9, [[0.1, 0.9, 8.9, 1.1, 3.7, 6.3]]),
        (7, 9, [[0, 0, 8, 0, 8, 2, 2, 2, 2, 6, 0, 6]]),
        (1, 1, [rect(-1, -1, 3, 3)]),
    ]
    for index, (height, width, polygons) in enumerate(fixed):
        yield "fixed-" + str(index), height, width, polygons
    rng = random.Random(SEED)
    fractions = (-0.500001, -0.5, -0.499999, -0.1, 0, 0.099999, 0.1, 0.100001, 0.499999, 0.5)
    for index in range(160):
        height, width = ((1, 1), (3, 7), (17, 13), (31, 29))[index % 4]
        polygons = []
        for ring in range(rng.randrange(1, 5)):
            points = [(rng.randrange(-3, width + 4) + rng.choice(fractions),
                       rng.randrange(-3, height + 4) + rng.choice(fractions))
                      for _ in range(rng.randrange(3, 12))]
            if index % 3:
                cx, cy = np.mean(points, axis=0)
                points.sort(key=lambda point: math.atan2(point[1] - cy, point[0] - cx))
            if index % 5 == 0:
                points.insert(1, points[0])
            if index % 7 == 0:
                points.append(points[0])
            polygons.append([value for point in points for value in point])
        yield "seeded-" + str(index), height, width, polygons


def geometry(name, height, width, polygons):
    expected = reference_mask(polygons, height, width)
    run = subprocess.run(
        ["moon", "run", "examples/rle_probe", "--target", "native", "--",
         "--segmentation", str(height), str(width), json.dumps(polygons), json.dumps(json_rle(expected))],
        cwd=evaluation.ROOT, text=True, encoding="utf-8", capture_output=True, timeout=30)
    assert run.returncode == 0, (name, run.stderr)
    result = json.loads(run.stdout)
    actual = {"size": [height, width], "counts": result["detection_counts"].encode("ascii")}
    assert np.array_equal(masks.decode(actual), masks.decode(expected)), (name, polygons, result, json_rle(expected))
    assert result["detection_area"] == int(masks.area(expected)), (name, result)
    expected_overlap = 1 if result["detection_area"] else 0
    assert result["iou"] == result["crowd_iou"] == expected_overlap


def ap_cases():
    for index, (name, height, width, polygons) in enumerate(fixtures()):
        if index >= 42:
            break
        truth = evaluation.dataset([evaluation.gt(1, 1, 1, json_rle(reference_mask(polygons, height, width)))], height, width)
        # Keep polygon input intact in the CLI; the reference normalizes its copy.
        truth["annotations"][0]["segmentation"] = polygons
        exact = evaluation.dt(1, 1, copy.deepcopy(polygons), 0.8)
        predictions = [evaluation.dt(1, 1, [rect(0, 0, width / 2, height / 2)], 0.9), exact, dict(copy.deepcopy(exact), score=0.4)]
        if index % 4 == 0:
            crowd = evaluation.gt(2, 1, 1, json_rle(reference_mask([rect(0, 0, width, height)], height, width)), crowd=1)
            truth["annotations"].append(crowd)
        yield name, height, width, truth, predictions


def check_cli():
    polygons = [rect(0, 0, 3, 3)]
    data = evaluation.dataset([evaluation.gt(1, 1, 1, json_rle(reference_mask(polygons, 4, 4)))], 4, 4)
    data["annotations"][0]["segmentation"] = polygons
    good = [evaluation.dt(1, 1, polygons)]
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        candidate = directory / "candidate.json"
        candidate.write_text(json.dumps(good), encoding="utf-8")
        output = directory / "report.json"
        run = evaluation.run_cli(data, [evaluation.dt(1, 1, json_rle(reference_mask(polygons, 4, 4)))], directory,
                                 "--compare", str(candidate), "--diagnostics", "--pr-curves", "--image-ranking",
                                 "--min-ap50", "1", "--output", str(output))
        assert run.returncode == 0, run.stderr
        paired = json.loads(output.read_text(encoding="utf-8"))
        assert all(row["delta"] == 0 for row in paired["metrics"] if row["delta"] is not None)
        assert paired["candidate"]["summary"]["ap"] == 1
        saved = output.read_bytes()
        run = evaluation.run_cli(data, good, directory, "--output", str(output))
        assert run.returncode == 2 and output.read_bytes() == saved
        invalid = [[], [[]], [[0, 0, 2, 0, 2]], [[0, 0, 2, 0, "2", 2]],
                   [[0, 0, 1000000, 0, 0, 1]], [[0, 0, 1e100, 0, 0, 1]]]
        for segmentation in invalid:
            run = evaluation.run_cli(data, [evaluation.dt(1, 1, segmentation)], directory, "--output", str(directory / "invalid.json"))
            assert run.returncode == 2 and "detections[0]" in run.stderr, (segmentation, run.stderr)
            assert not (directory / "invalid.json").exists()
        bad_truth = copy.deepcopy(data)
        bad_truth["annotations"][0]["segmentation"] = [[0, 0, 2, 0, False, 2]]
        run = evaluation.run_cli(bad_truth, good, directory)
        assert run.returncode == 2 and "annotations[0]" in run.stderr and "segmentation[0][4]" in run.stderr
        run = evaluation.run_cli(data, [evaluation.dt(99, 1, polygons)], directory)
        assert run.returncode == 2 and "detections[0]" in run.stderr
    print("polygon CLI mixed-RLE comparison/output/errors/work-limits: OK")


def main():
    assert importlib.metadata.version("pycocotools") == "2.0.7"
    count = 0
    for name, height, width, polygons in fixtures():
        geometry(name, height, width, polygons)
        count += 1
    print(str(count) + " polygon geometries: exact reference pixels/areas/IoU")
    diagnostics = samples = ap_count = 0
    for name, height, width, truth, predictions in ap_cases():
        checked, points = evaluation.compare("polygon-AP-" + name, truth, predictions)
        diagnostics += checked
        samples += points
        ap_count += 1
    check_cli()
    print(json.dumps({"seed": SEED, "geometry_cases": count, "AP_cases": ap_count,
                      "diagnostic_entries": diagnostics, "PR_samples": samples}))


if __name__ == "__main__":
    main()
