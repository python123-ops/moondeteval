"""Compare MoonBit RLE geometry and compressed/JSON codecs with pycocotools 2.0.7."""

import importlib.metadata
import json
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
    encoded = [detection["counts"].decode("ascii"), truth["counts"].decode("ascii")]
    argument_sets = [
        [str(height), str(width), ",".join(map(str, detection_counts)),
         ",".join(map(str, truth_counts))],
        ["--json", json.dumps({"size": [height, width], "counts": encoded[0]}),
         json.dumps({"size": [height, width], "counts": encoded[1]})],
        ["--json", json.dumps({"size": [height, width], "counts": detection_counts}),
         json.dumps({"size": [height, width], "counts": truth_counts})],
    ]
    for arguments in argument_sets:
        command = ["moon", "run", "examples/rle_probe", "--target", "native", "--"] + arguments
        run = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30)
        assert run.returncode == 0, (command, run.stderr)
        result = json.loads(run.stdout)
        actual = [result[key] for key in ("detection_area", "truth_area", "iou", "crowd_iou")]
        assert all(
            math.isclose(left, right, rel_tol=0, abs_tol=1e-12)
            for left, right in zip(actual, expected)
        ), (command, actual, expected)
        exported = [result["detection_counts"], result["truth_counts"]]
        assert exported == encoded, (command, exported, encoded)
        # Read MoonBit exports with the C reference without raster expansion.
        roundtrip = [{"size": [height, width], "counts": value.encode("ascii")}
                     for value in exported]
        assert [float(coco_mask.area(value)) for value in roundtrip] == expected[:2]


def main():
    assert importlib.metadata.version("pycocotools") == "2.0.7"
    cases = [
        (3, 4, [1, 2, 2, 3, 4], [0, 3, 2, 1, 6]),
        (2, 3, [6], [0, 6]),
        (2, 3, [6], [6]),
        (2, 3, [0, 6], [0, 6]),
        (2, 3, [0, 0, 0, 3, 3], [3, 3]),
        (1, 1, [1], [0, 1]),
        (1, 1, [0, 1], [0, 1]),
        (1, 45, [0, 44, 1], [1, 44]),
        (1, 220, [0, 100, 0, 1, 0, 119], [0, 220]),
        (1, 100, [0, 40, 1, 1, 1, 57], [0, 100]),
        # The Windows 2.0.7 C decoder mishandles some seven-group signed
        # deltas. Int-limit cases have explicit MoonBit black-box fixtures;
        # keep reference geometry comparisons within a reliable C range.
        (1, 214747, [0, 100000, 0, 1, 0, 114746], [0, 214747]),
    ]
    rng = random.Random(SEED)
    for height, width in ((1, 9), (3, 7), (13, 11)):
        for _ in range(8):
            detection = [int(rng.random() < 0.35) for _ in range(height * width)]
            truth = [int(rng.random() < 0.55) for _ in range(height * width)]
            cases.append((height, width, runs(detection), runs(truth)))
    for case in cases:
        compare(*case)
    print(f"{len(cases)} RLE pairs in 3 input forms match pycocotools 2.0.7; "
          f"compressed counts match byte-for-byte; seed={SEED}")


if __name__ == "__main__":
    main()
