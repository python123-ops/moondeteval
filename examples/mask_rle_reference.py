"""Compare MoonBit uncompressed RLE primitives with pycocotools 2.0.7."""

import importlib.metadata
import math
import random
import subprocess
from pathlib import Path

from pycocotools import mask as coco_mask


ROOT = Path(__file__).resolve().parents[1]
SEED = 20261011


def runs(bits):
    result = []
    current = 0
    length = 0
    for bit in bits:
        if bit != current:
            result.append(length)
            current = bit
            length = 0
        length += 1
    result.append(length)
    return result


def compare(height, width, detection_counts, truth_counts):
    command = [
        "moon", "run", "examples/rle_probe", "--target", "native", "--",
        str(height), str(width), ",".join(map(str, detection_counts)),
        ",".join(map(str, truth_counts)),
    ]
    run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    assert run.returncode == 0, (command, run.stderr)
    actual = [float(value) for value in run.stdout.split()]
    detection = coco_mask.frPyObjects(
        {"size": [height, width], "counts": detection_counts}, height, width,
    )
    truth = coco_mask.frPyObjects(
        {"size": [height, width], "counts": truth_counts}, height, width,
    )
    expected = [
        float(coco_mask.area(detection)), float(coco_mask.area(truth)),
        float(coco_mask.iou([detection], [truth], [0])[0, 0]),
        float(coco_mask.iou([detection], [truth], [1])[0, 0]),
    ]
    assert len(actual) == 4 and all(
        math.isclose(left, right, rel_tol=0, abs_tol=1e-12)
        for left, right in zip(actual, expected)
    ), (command, actual, expected)


def main():
    assert importlib.metadata.version("pycocotools") == "2.0.7"
    cases = [
        (3, 4, [1, 2, 2, 3, 4], [0, 3, 2, 1, 6]),
        (2, 3, [6], [0, 6]),
        (2, 3, [6], [6]),
        (2, 3, [0, 6], [0, 6]),
        (2, 3, [0, 0, 0, 3, 3], [3, 3]),
    ]
    rng = random.Random(SEED)
    for height, width in ((1, 9), (3, 7), (13, 11)):
        for _ in range(8):
            detection = [int(rng.random() < 0.35) for _ in range(height * width)]
            truth = [int(rng.random() < 0.55) for _ in range(height * width)]
            cases.append((height, width, runs(detection), runs(truth)))
    for case in cases:
        compare(*case)
    print(f"{len(cases)} uncompressed RLE pairs match pycocotools 2.0.7; seed={SEED}")


if __name__ == "__main__":
    main()
