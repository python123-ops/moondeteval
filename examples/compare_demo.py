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
        encoding="utf-8",
    )


def main():
    result = run("--diagnostics", "--image-ranking", "--pr-curves")
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
    assert report["baseline"]["image_summaries"] == [
        {"image_id": 1, "tp": 2, "fp": 0, "fn_count": 0, "ignored": 0}
    ]
    assert report["candidate"]["image_summaries"] == [
        {"image_id": 1, "tp": 1, "fp": 3, "fn_count": 1, "ignored": 0}
    ]
    assert report["image_changes"] == [
        {"image_id": 1, "baseline_errors": 0, "candidate_errors": 4,
         "error_delta": 4}
    ]
    assert len(report["baseline"]["recall_thresholds"]) == 101
    assert len(report["baseline"]["pr_curves"]) == 20
    assert len(report["candidate"]["pr_curves"]) == 20
    for side in ("baseline", "candidate"):
        for curve in report[side]["pr_curves"]:
            assert len(curve["precision"]) == 101
            if curve["ap"] >= 0:
                assert abs(sum(curve["precision"]) / 101 - curve["ap"]) < 1e-9
    assert report["baseline"]["pr_curves"][0]["ap"] == 1
    assert report["candidate"]["pr_curves"][0]["ap"] == 0

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
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
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
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
        )
        assert shared_warning.returncode == 3, shared_warning.stderr
        assert "1 out-of-image warning(s)" in shared_warning.stderr

        for options in (("--max-records", "1"), ("--max-report-bytes", "1")):
            blocked_path = directory / "blocked.json"
            blocked = run(*options, "--output", str(blocked_path))
            assert blocked.returncode == 2, blocked.stderr
            assert not blocked_path.exists()

        repeated = run("--image-ranking", "--image-ranking")
        assert repeated.returncode == 2
        assert "may only be given once" in repeated.stderr
        repeated_curves = run("--pr-curves", "--pr-curves")
        assert repeated_curves.returncode == 2
        assert "may only be given once" in repeated_curves.stderr

        compact = run()
        assert compact.returncode == 0, compact.stderr
        timed = run("--timings")
        assert timed.returncode == 0, timed.stderr
        assert timed.stdout == compact.stdout
        assert "timings_us input=" in timed.stderr
        assert "evaluation=" in timed.stderr and "serialization=" in timed.stderr
        repeated_timings = run("--timings", "--timings")
        assert repeated_timings.returncode == 2
        exact_bytes = len(compact.stdout.encode("utf-8"))
        assert run("--max-report-bytes", str(exact_bytes)).returncode == 0
        assert run("--max-report-bytes", str(exact_bytes - 1)).returncode == 2
        records = (
            report["baseline"]["counts"]["images"]
            + report["baseline"]["counts"]["categories"]
            + report["baseline"]["counts"]["ground_truths"]
            + report["baseline"]["counts"]["detections"]
            + report["candidate"]["counts"]["detections"]
        )
        assert run("--max-records", str(records)).returncode == 0
        assert run("--max-records", str(records - 1)).returncode == 2
        largest_input = max(path.stat().st_size for path in (GROUND_TRUTH, BASELINE, CANDIDATE))
        total_input = sum(path.stat().st_size for path in (GROUND_TRUTH, BASELINE, CANDIDATE))
        assert run("--max-input-bytes", str(largest_input)).returncode == 0
        assert run("--max-input-bytes", str(largest_input - 1)).returncode == 2
        assert run("--max-total-input-bytes", str(total_input)).returncode == 0
        assert run("--max-total-input-bytes", str(total_input - 1)).returncode == 2
        diagnostic_bound = 10 * (
            report["baseline"]["counts"]["detections"]
            + report["candidate"]["counts"]["detections"]
            + 2 * report["baseline"]["counts"]["ground_truths"]
        )
        assert run("--diagnostics", "--max-diagnostics", str(diagnostic_bound)).returncode == 0
        assert run("--diagnostics", "--max-diagnostics", str(diagnostic_bound - 1)).returncode == 2
        curve_limit = len(compact.stdout) + 10
        curves_path = directory / "oversized-curves.json"
        oversized_curves = run(
            "--pr-curves", "--max-report-bytes", str(curve_limit),
            "--output", str(curves_path),
        )
        assert oversized_curves.returncode == 2, oversized_curves.stderr
        assert "report exceeds --max-report-bytes" in oversized_curves.stderr
        assert not curves_path.exists()

        reused_path = run("--output", str(CANDIDATE))
        assert reused_path.returncode == 2
        assert "output path must differ" in reused_path.stderr
        for input_path in (GROUND_TRUTH, BASELINE):
            reused = run("--output", str(input_path))
            assert reused.returncode == 2 and "output path must differ" in reused.stderr

        existing = directory / "existing.json"
        existing.write_bytes(b"keep original bytes")
        assert run("--output", str(existing)).returncode == 2
        assert existing.read_bytes() == b"keep original bytes"
        target = directory / "target.json"
        temporary = directory / "target.json.moondeteval.tmp"
        temporary.write_bytes(b"keep temporary bytes")
        collision = run("--output", str(target))
        assert collision.returncode == 2 and "temporary output" in collision.stderr
        assert temporary.read_bytes() == b"keep temporary bytes"
        assert not target.exists()

        malformed = directory / "malformed.json"
        malformed.write_text('[{"image_id":', encoding="utf-8")
        bad_output = directory / "bad-output.json"
        bad = subprocess.run(
            ["moon", "run", "cli", "--target", "native", "--", str(GROUND_TRUTH),
             str(malformed), "--output", str(bad_output)],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
        )
        assert bad.returncode == 2 and "not valid JSON" in bad.stderr
        assert not bad_output.exists()
        for field, unknown in (("image_id", 999), ("category_id", 999)):
            invalid = directory / f"unknown-{field}.json"
            rows = json.loads(BASELINE.read_text(encoding="utf-8"))
            rows[0][field] = unknown
            invalid.write_text(json.dumps(rows), encoding="utf-8")
            result = subprocess.run(
                ["moon", "run", "cli", "--target", "native", "--", str(GROUND_TRUTH),
                 str(invalid), "--output", str(bad_output)],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
            )
            assert result.returncode == 2
            assert str(invalid) in result.stderr and f"detections[0].{field}" in result.stderr
            assert not bad_output.exists()

    print(f"AP50: baseline {ap50['baseline']}, candidate {ap50['candidate']}, delta {ap50['delta']}")
    for detection_id, reason in sorted(errors.items()):
        print(f"candidate detection {detection_id}: {reason}")
    print("image 1: baseline errors 0, candidate errors 4, delta +4")
    print("20 PR curves per detector, 101 samples each; AP equals the sample mean")
    print("AP50 and quality gates returned code 3 with complete reports")


if __name__ == "__main__":
    main()
