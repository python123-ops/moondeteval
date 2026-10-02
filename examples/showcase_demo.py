"""Show a reproducible detector regression using the checked-in synthetic fixture."""

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "examples"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cli",
        type=Path,
        help="installed MoonDetEval native CLI; default runs the source checkout",
    )
    args = parser.parse_args()
    prefix = [str(args.cli.resolve())] if args.cli else [
        "moon", "run", "cli", "--target", "native", "--"
    ]
    command = prefix + [
        str(FIXTURES / "compare-ground-truth.json"),
        str(FIXTURES / "compare-baseline.json"),
        "--compare", str(FIXTURES / "compare-candidate.json"),
        "--diagnostics", "--image-ranking", "--pr-curves",
    ]
    completed = subprocess.run(
        command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8"
    )
    if completed.returncode:
        raise RuntimeError(f"CLI exited {completed.returncode}: {completed.stderr}")
    report = json.loads(completed.stdout)
    assert report["schema_version"] == "0.1.0"
    ap50 = next(metric for metric in report["metrics"] if metric["name"] == "ap50")
    assert (ap50["baseline"], ap50["candidate"], ap50["delta"]) == (
        1, 0.25, -0.75
    )
    candidate = report["candidate"]
    fp = sorted(
        (item["detection_id"], item["reason"])
        for item in candidate["diagnostics"]
        if item["iou_threshold"] == 0.5 and item["status"] == "fp"
    )
    fn = sorted(
        item["ground_truth_id"]
        for item in candidate["diagnostics"]
        if item["iou_threshold"] == 0.5 and item["status"] == "fn"
    )
    assert fp == [(0, "wrong_class"), (1, "localization"), (3, "duplicate")]
    assert fn == [101]
    assert report["image_changes"] == [
        {"image_id": 1, "baseline_errors": 0,
         "candidate_errors": 4, "error_delta": 4}
    ]
    curves = [
        item for item in candidate["pr_curves"]
        if item["iou_threshold"] == 0.5
    ]
    assert [(item["category_id"], item["ap"]) for item in curves] == [
        (1, 0), (2, 0.5)
    ]
    assert all(len(item["precision"]) == 101 for item in curves)
    print("MoonDetEval 0.1.0 | synthetic detector comparison")
    print("AP50: baseline=1 candidate=0.25 delta=-0.75")
    print("IoU 0.50 FP: #0 wrong_class, #1 localization, #3 duplicate")
    print("IoU 0.50 FN: ground-truth #101")
    print("Image #1: baseline errors=0 candidate errors=4 delta=+4")
    print("PR@0.50: category #1 AP=0; category #2 AP=0.5 (101 points each)")


if __name__ == "__main__":
    main()
