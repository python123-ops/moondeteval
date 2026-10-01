"""Run a synthetic two-detector comparison using only the Python standard library."""

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GROUND_TRUTH = ROOT / "examples/compare-ground-truth.json"
BASELINE = ROOT / "examples/compare-baseline.json"
CANDIDATE = ROOT / "examples/compare-candidate.json"
COMMAND = [
    "moon", "run", "cli", "--target", "native", "--",
    str(GROUND_TRUTH), str(BASELINE), "--compare", str(CANDIDATE),
]


def run(*options):
    return subprocess.run(
        COMMAND + list(options), cwd=ROOT, capture_output=True, text=True,
    )


def main():
    result = run("--diagnostics")
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    ap50 = next(item for item in report["metrics"] if item["name"] == "ap50")
    assert (ap50["baseline"], ap50["candidate"], ap50["delta"]) == (1, 0.25, -0.75)
    assert len(report["metrics"]) == 12
    errors = {
        item["detection_id"]: item["reason"]
        for item in report["candidate"]["diagnostics"]
        if item["iou_threshold"] == 0.5 and item["status"] == "fp"
    }
    assert errors == {0: "wrong_class", 1: "localization", 3: "duplicate"}, errors

    with tempfile.TemporaryDirectory() as directory:
        directory = Path(directory)
        gate_path = directory / "failed-gate.json"
        gated = run("--min-ap50", "0.5", "--output", str(gate_path))
        assert gated.returncode == 3, gated.stderr
        assert json.loads(gate_path.read_text(encoding="utf-8"))["candidate"]["summary"]["ap50"] == 0.25

        outside = directory / "outside.json"
        predictions = json.loads(CANDIDATE.read_text(encoding="utf-8"))
        predictions[0]["bbox"][0] = -1
        outside.write_text(json.dumps(predictions), encoding="utf-8")
        warning_path = directory / "warning-gate.json"
        warned = subprocess.run(
            ["moon", "run", "cli", "--target", "native", "--", str(GROUND_TRUTH),
             str(BASELINE), "--compare", str(outside), "--fail-on-warning",
             "--output", str(warning_path)],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert warned.returncode == 3, warned.stderr
        warning_report = json.loads(warning_path.read_text(encoding="utf-8"))
        assert warning_report["candidate"]["quality_warnings"][0]["record_id"] == 0

        outside_truth = directory / "outside-truth.json"
        truth = json.loads(GROUND_TRUTH.read_text(encoding="utf-8"))
        truth["annotations"][0]["bbox"][0] = -1
        outside_truth.write_text(json.dumps(truth), encoding="utf-8")
        shared_warning = subprocess.run(
            ["moon", "run", "cli", "--target", "native", "--", str(outside_truth),
             str(BASELINE), "--compare", str(CANDIDATE), "--fail-on-warning"],
            cwd=ROOT, capture_output=True, text=True,
        )
        assert shared_warning.returncode == 3, shared_warning.stderr
        assert "1 out-of-image warning(s)" in shared_warning.stderr

        for options in (("--max-records", "1"), ("--max-report-bytes", "1")):
            blocked_path = directory / "blocked.json"
            blocked = run(*options, "--output", str(blocked_path))
            assert blocked.returncode == 2, blocked.stderr
            assert not blocked_path.exists()

        reused_path = run("--output", str(CANDIDATE))
        assert reused_path.returncode == 2
        assert "output path must differ" in reused_path.stderr

    print(f"AP50: baseline {ap50['baseline']}, candidate {ap50['candidate']}, delta {ap50['delta']}")
    for detection_id, reason in sorted(errors.items()):
        print(f"candidate detection {detection_id}: {reason}")
    print("AP50 and quality gates returned code 3 with complete reports")


if __name__ == "__main__":
    main()
