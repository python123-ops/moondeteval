"""Exercise native multi-image YOLO loading and COCO/YOLO parity (stdlib only)."""

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "examples/yolo"
TRUTH = FIXTURE / "ground-truth.json"
COCO = FIXTURE / "detections.json"
MANIFEST = FIXTURE / "manifest.json"
BASE = ["moon", "run", "cli", "--target", "native", "--", str(TRUTH)]


def run(source, *options):
    return subprocess.run(
        BASE + [str(source), *map(str, options)],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )


def expect_failure(source, directory, *options, contains=None):
    output = directory / "blocked.json"
    result = run(source, *options, "--output", output)
    assert result.returncode == 2, (result.returncode, result.stderr)
    assert not output.exists(), output
    assert not Path(str(output) + ".moondeteval.tmp").exists()
    if contains:
        assert contains in result.stderr, result.stderr


def main():
    coco = run(COCO, "--diagnostics")
    yolo = run(MANIFEST, "--prediction-format", "yolo", "--diagnostics")
    assert coco.returncode == yolo.returncode == 0, (coco.stderr, yolo.stderr)
    coco_report = json.loads(coco.stdout)
    yolo_report = json.loads(yolo.stdout)
    for field in ("summary", "classes", "diagnostics", "quality_warnings", "counts"):
        assert yolo_report[field] == coco_report[field], field
    assert len(yolo_report["summary"]) == 12
    assert yolo_report["summary"]["ap50"] == 0.5
    assert yolo_report["counts"]["detections"] == 1
    assert yolo_report["diagnostics"][0]["detection_id"] == 0

    mixed = run(COCO, "--compare", MANIFEST, "--compare-format", "yolo", "--diagnostics")
    assert mixed.returncode == 0, mixed.stderr
    comparison = json.loads(mixed.stdout)
    assert comparison["baseline"] == comparison["candidate"] == coco_report
    assert len(comparison["metrics"]) == 12
    assert all(item["delta"] in (0, None) for item in comparison["metrics"])
    assert all(
        item["delta"] in (0, None)
        for category in comparison["classes"]
        for item in category["metrics"]
    )

    reverse = run(MANIFEST, "--prediction-format", "yolo", "--compare", COCO)
    assert reverse.returncode == 0, reverse.stderr
    reverse_report = json.loads(reverse.stdout)
    assert reverse_report["baseline"]["summary"]["ap50"] == 0.5
    assert reverse_report["candidate"]["summary"]["ap50"] == 0.5
    assert all(item["delta"] in (0, None) for item in reverse_report["metrics"])

    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        labels = directory / "labels"
        labels.mkdir()
        (labels / "image-9.txt").write_text("0 0.25 0.5 0.5 0.4 0.9\n", encoding="utf-8")
        (labels / "image-12.txt").write_text("\n", encoding="utf-8")
        document = json.loads(MANIFEST.read_text(encoding="utf-8"))
        manifest = directory / "manifest.json"

        def write_manifest():
            manifest.write_text(json.dumps(document), encoding="utf-8")

        write_manifest()
        (labels / "image-12.txt").write_text("1 0.3 0.3 0.2 0.2 0.8\n", encoding="utf-8")
        ordered = run(manifest, "--prediction-format", "yolo", "--diagnostics")
        assert ordered.returncode == 0, ordered.stderr
        ordered_report = json.loads(ordered.stdout)
        assert ordered_report["summary"]["ap50"] == 1
        first_threshold = [
            item for item in ordered_report["diagnostics"]
            if item["iou_threshold"] == 0.5 and item["status"] == "tp"
        ]
        assert {(item["image_id"], item["detection_id"]) for item in first_threshold} == {
            (12, 0), (9, 1)
        }
        (labels / "image-12.txt").write_text("\n", encoding="utf-8")

        (labels / "image-9.txt").unlink()
        expect_failure(manifest, directory, "--prediction-format", "yolo", contains="image-9.txt")
        (labels / "image-9.txt").write_text("0 0.25 0.5 0.5 0.4 0.9\n", encoding="utf-8")

        document["images"].append(document["images"][0])
        write_manifest()
        expect_failure(manifest, directory, "--prediction-format", "yolo", contains="duplicated")
        document["images"].pop()
        document["category_ids"][0] = 999
        write_manifest()
        expect_failure(manifest, directory, "--prediction-format", "yolo", contains="category_ids[0]")
        document["category_ids"][0] = 42
        write_manifest()

        (labels / "image-9.txt").write_text("0 1.1 0.5 0.5 0.4 0.9\n", encoding="utf-8")
        expect_failure(manifest, directory, "--prediction-format", "yolo", contains="image-9.txt")
        (labels / "image-9.txt").write_text("0 0.25 0.5 0.5 0.4\n", encoding="utf-8")
        expect_failure(manifest, directory, "--prediction-format", "yolo", contains="line 1")
        (labels / "image-9.txt").write_text("0 0.25 0.5 0.5 0.4 0.9\n", encoding="utf-8")

        per_file = max(len(TRUTH.read_bytes()), len(manifest.read_bytes()))
        expect_failure(
            manifest, directory, "--prediction-format", "yolo",
            "--max-input-bytes", 1, contains="--max-input-bytes",
        )
        total = len(TRUTH.read_bytes()) + len(manifest.read_bytes())
        expect_failure(
            manifest, directory, "--prediction-format", "yolo",
            "--max-input-bytes", per_file,
            "--max-total-input-bytes", total, contains="--max-total-input-bytes",
        )
        expect_failure(
            manifest, directory, "--prediction-format", "yolo",
            "--max-records", 1, contains="--max-records",
        )
        expect_failure(
            manifest, directory, "--prediction-format", "yolo",
            "--max-report-bytes", 1, contains="--max-report-bytes",
        )
        expect_failure(COCO, directory, "--compare-format", "yolo", contains="requires --compare")

        gate = directory / "gate.json"
        gated = run(manifest, "--prediction-format", "yolo", "--min-ap50", 0.8, "--output", gate)
        assert gated.returncode == 3, gated.stderr
        assert json.loads(gate.read_text(encoding="utf-8"))["summary"]["ap50"] == 0.5
        reused = run(manifest, "--prediction-format", "yolo", "--output", gate)
        assert reused.returncode == 2 and "already exists" in reused.stderr

        (labels / "image-9.txt").write_text("0 0.1 0.5 0.5 0.4 0.9\n", encoding="utf-8")
        warning_path = directory / "warning.json"
        warned = run(
            manifest, "--prediction-format", "yolo", "--fail-on-warning",
            "--output", warning_path,
        )
        assert warned.returncode == 3, warned.stderr
        warning_report = json.loads(warning_path.read_text(encoding="utf-8"))
        assert warning_report["quality_warnings"][0]["record_id"] == 0

    print("COCO and multi-image YOLO: all 12 summary metrics, classes and diagnostics identical")
    print("Mixed-format comparison: 12 zero/undefined deltas; AP50=0.5")
    print("Malformed inputs and resource limits: exit 2 without an output; both gates: exit 3 with complete reports")


if __name__ == "__main__":
    main()
