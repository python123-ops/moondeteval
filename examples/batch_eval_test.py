"""Integration checks for the source-checkout batch evaluator."""

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "examples/batch_eval.py"
TRUTH = ROOT / "examples/compare-ground-truth.json"
BASE = ROOT / "examples/compare-baseline.json"
CANDIDATE = ROOT / "examples/compare-candidate.json"


def batch(output, *extra):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--ground-truth", str(TRUTH),
         "--model", "baseline", str(BASE), "--model", "candidate", str(CANDIDATE),
         "--baseline", "baseline", "--output-dir", str(output), *extra],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
    )


class BatchEvaluationTest(unittest.TestCase):
    def test_reports_agree_with_native_pairwise_comparison_and_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "batch"
            result = batch(output, "--diagnostics", "--image-ranking", "--pr-curves")
            self.assertEqual(result.returncode, 0, result.stderr)
            index = json.loads((output / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(index["ground_truth_sha256"], hashlib.sha256(TRUTH.read_bytes()).hexdigest())
            self.assertEqual(index["baseline"], "baseline")
            self.assertEqual(len(index["models"]), 2)
            direct = subprocess.run(
                ["moon", "run", "cli", "--target", "native", "--", str(TRUTH), str(BASE),
                 "--compare", str(CANDIDATE), "--diagnostics", "--image-ranking", "--pr-curves"],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(direct.returncode, 0, direct.stderr)
            paired = json.loads(direct.stdout)
            for entry, side in zip(index["models"], ("baseline", "candidate")):
                report_path = output / entry["report_file"]
                report = json.loads(report_path.read_text(encoding="utf-8"))
                self.assertEqual(report["summary"], paired[side]["summary"])
                self.assertEqual(entry["report_sha256"], hashlib.sha256(report_path.read_bytes()).hexdigest())
                self.assertEqual(entry["prediction_sha256"], hashlib.sha256(Path(entry["prediction_path"]).read_bytes()).hexdigest())
                self.assertEqual(entry["summary"], report["summary"])
                self.assertEqual(entry["delta_from_baseline"]["ap_medium"], None)
                self.assertEqual(entry["replay_command"][-1], "--pr-curves")
            self.assertEqual(index["models"][1]["delta_from_baseline"]["ap50"], -0.75)
            self.assertEqual({p.name for p in output.iterdir()},
                             {"index.json", "baseline.report.json", "candidate.report.json"})

    def test_bad_second_input_leaves_no_output_and_rejects_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            output = parent / "batch"
            bad = parent / "bad.json"
            bad.write_text("{", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--ground-truth", str(TRUTH),
                 "--model", "baseline", str(BASE), "--model", "bad", str(bad),
                 "--baseline", "baseline", "--output-dir", str(output)],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(result.returncode, 2)
            self.assertFalse(output.exists())
            self.assertEqual(list(parent.iterdir()), [bad])
            output.mkdir()
            marker = output / "keep.txt"
            marker.write_text("keep", encoding="utf-8")
            repeated = batch(output)
            self.assertEqual(repeated.returncode, 2)
            self.assertEqual(marker.read_text(encoding="utf-8"), "keep")

    def test_model_names_and_baseline_are_checked_before_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "batch"
            for name in ("baseline", "BASELINE", "CON", "../outside"):
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), "--ground-truth", str(TRUTH),
                     "--model", "baseline", str(BASE), "--model", name, str(CANDIDATE),
                     "--baseline", "baseline", "--output-dir", str(output)],
                    cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
                )
                self.assertEqual(result.returncode, 2, name)
                self.assertFalse(output.exists())
            missing = batch(output, "--max-report-bytes", "0")
            self.assertEqual(missing.returncode, 2)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
