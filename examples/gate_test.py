"""Exercise metric gates through real native CLI processes."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
import hashlib

ROOT = Path(__file__).resolve().parents[1]
TRUTH = ROOT / "examples/compare-ground-truth.json"
BASE = ROOT / "examples/compare-baseline.json"
CANDIDATE = ROOT / "examples/compare-candidate.json"


class MetricGateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["moon", "build", "cli", "--target", "native", "--release"], cwd=ROOT, check=True, capture_output=True)
        folder = ROOT / "_build/native/release/build/cli"
        cls.cli = next(folder / name for name in ("cli.exe", "cli") if (folder / name).is_file())

    def run_cli(self, *flags, paired=True, truth=TRUTH, prediction=BASE):
        args = [str(self.cli), str(truth), str(prediction)]
        if paired:
            args += ["--compare", str(CANDIDATE)]
        return subprocess.run(args + list(map(str, flags)), cwd=ROOT, capture_output=True, text=True, encoding="utf-8")

    def test_failed_drop_keeps_complete_paired_report_and_exit_three(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            result = self.run_cli("--max-metric-drop", "ap50=0.1", "--diagnostics", "--output", output)
            self.assertEqual(result.returncode, 3, result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["candidate"]["summary"]["ap50"], .25)
            self.assertTrue(report["candidate"]["diagnostics"])
            self.assertEqual(report["metric_gates"]["checks"][0]["drop"], .75)
            self.assertEqual(report["metric_gates"]["checks"][0]["reason"], "drop_exceeded")

    def test_absolute_single_and_inclusive_comparison_rules(self):
        single = self.run_cli("--min-metric", "ap50=1", paired=False)
        self.assertEqual(single.returncode, 0, single.stderr)
        self.assertEqual(json.loads(single.stdout)["metric_gates"]["status"], "passed")
        pair = self.run_cli("--min-metric", "ap50=0.25", "--max-metric-drop", "ap50=0.75")
        self.assertEqual(pair.returncode, 0, pair.stderr)
        self.assertEqual(len(json.loads(pair.stdout)["metric_gates"]["checks"]), 2)

    def test_invalid_rules_never_write_an_output(self):
        cases = [
            ["--min-metric", "accuracy=0"], ["--min-metric", "ap=NaN"], ["--min-metric", "ap=inf"],
            ["--min-metric", "ap=-0.1"], ["--min-metric", "ap=1.1"], ["--min-metric", "ap"],
            ["--min-metric", "ap=0", "--min-metric", "ap=0.1"], ["--min-class-metric", "999:ap=0"],
            ["--min-class-metric", "2147483648:ap=0"], ["--min-class-metric", "1.5:ap=0"],
            ["--min-class-metric", "1:ap=0=1"], ["--undefined-gate", "skip"],
            ["--min-metric", "ap=0", "--min-ap50", "0"], ["--min-metric", "ap=0", "--undefined-gate", "other"],
        ]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            for flags in cases:
                with self.subTest(flags=flags):
                    result = self.run_cli(*flags, "--output", output)
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertFalse(output.exists())
        self.assertEqual(self.run_cli("--max-metric-drop", "ap=0.1", paired=False).returncode, 2)

    def test_undefined_metrics_and_all_skipped_are_not_false_success(self):
        failed = self.run_cli("--min-metric", "ap_large=0", paired=False)
        self.assertEqual(failed.returncode, 3)
        self.assertIsNone(json.loads(failed.stdout)["metric_gates"]["checks"][0]["candidate"])
        skipped = self.run_cli("--min-metric", "ap_large=0", "--undefined-gate", "skip", paired=False)
        self.assertEqual(skipped.returncode, 3)
        self.assertEqual(json.loads(skipped.stdout)["metric_gates"]["reason"], "all_skipped")
        mixed = self.run_cli("--min-metric", "ap_large=0", "--min-metric", "ap=0", "--undefined-gate", "skip", paired=False)
        self.assertEqual(mixed.returncode, 0, mixed.stderr)

    def test_all_twelve_metrics_and_legacy_output(self):
        metrics = ["ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large", "ar1", "ar10", "ar100", "ar_small", "ar_medium", "ar_large"]
        flags = [item for name in metrics for item in ("--min-metric", name + "=0")]
        result = self.run_cli(*flags, "--undefined-gate", "skip")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([row["metric"] for row in json.loads(result.stdout)["metric_gates"]["checks"]], metrics)
        legacy = self.run_cli("--min-ap50", "0.5")
        self.assertEqual(legacy.returncode, 3)
        self.assertNotIn("metric_gates", json.loads(legacy.stdout))
        self.assertNotIn("metric_gates", json.loads(self.run_cli().stdout))

    def test_signed_category_zero_detections_and_no_truth(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            truth = json.loads((ROOT / "examples/mask-ground-truth.json").read_text(encoding="utf-8"))
            predictions = json.loads((ROOT / "examples/mask-candidate.json").read_text(encoding="utf-8"))
            truth["categories"][0]["id"] = -7
            truth["annotations"][0]["category_id"] = -7
            predictions[0]["category_id"] = -7
            gt, dt = folder / "gt.json", folder / "dt.json"
            gt.write_text(json.dumps(truth), encoding="utf-8")
            dt.write_text(json.dumps(predictions), encoding="utf-8")
            flags = ["--iou-type", "segm", "--min-class-metric", "-7:ap=1"]
            result = self.run_cli(*flags, paired=False, truth=gt, prediction=dt)
            self.assertEqual(result.returncode, 0, result.stderr)
            dt.write_text("[]", encoding="utf-8")
            self.assertEqual(self.run_cli("--iou-type", "segm", "--min-metric", "ap=0", paired=False, truth=gt, prediction=dt).returncode, 0)
            truth["annotations"] = []
            gt.write_text(json.dumps(truth), encoding="utf-8")
            self.assertEqual(self.run_cli("--iou-type", "segm", "--min-metric", "ap=0", paired=False, truth=gt, prediction=dt).returncode, 3)

    def test_gate_metadata_counts_toward_report_limit_and_existing_files_are_safe(self):
        plain = self.run_cli(paired=False)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "report.json"
            limited = self.run_cli("--min-metric", "ap=0", "--max-report-bytes", len(plain.stdout.encode("utf-8")) + 10, "--output", output, paired=False)
            self.assertEqual(limited.returncode, 2)
            self.assertFalse(output.exists())
            output.write_text("keep", encoding="utf-8")
            result = self.run_cli("--max-metric-drop", "ap=0", "--output", output)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "keep")

    def batch(self, output, *flags, invalid=None):
        args = [sys.executable, str(ROOT / "examples/batch_eval.py"), "--cli", str(self.cli),
                "--ground-truth", str(TRUTH), "--baseline", "baseline", "--output-dir", str(output),
                "--model", "bad", str(CANDIDATE), "--model", "good", str(BASE), "--model", "baseline", str(BASE)]
        if invalid is not None:
            args += ["--model", "invalid", str(invalid)]
        return subprocess.run(args + list(map(str, flags)), cwd=ROOT, capture_output=True, text=True, encoding="utf-8")

    def test_batch_finishes_all_candidates_keeps_order_and_records_complete_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bundle"
            result = self.batch(output, "--min-metric", "ap50=0.5", "--max-metric-drop", "ap50=0.1")
            self.assertEqual(result.returncode, 3, result.stderr)
            index = json.loads((output / "index.json").read_text(encoding="utf-8"))
            self.assertEqual([entry["name"] for entry in index["models"]], ["bad", "good", "baseline"])
            self.assertEqual(index["metric_gates"]["failed_models"], ["bad"])
            self.assertEqual(index["metric_gates"]["checked_models"], 2)
            self.assertEqual(index["metric_gates"]["rules"][1]["kind"], "max_drop")
            self.assertNotIn("metric_gates", index["models"][2])
            for entry in index["models"]:
                data = (output / entry["report_file"]).read_bytes()
                report = json.loads(data)
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["report_sha256"])
                if entry["name"] != "baseline":
                    self.assertEqual(report["metric_gates"], entry["metric_gates"])
                    self.assertEqual(entry["report_source"], "comparison.candidate")
            self.assertEqual({p.name for p in output.iterdir()}, {"index.json", "bad.report.json", "good.report.json", "baseline.report.json"})

    def test_minimum_only_batch_uses_single_reports_and_all_pass_returns_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bundle"
            result = self.batch(output, "--min-metric", "ap50=0.2")
            self.assertEqual(result.returncode, 0, result.stderr)
            index = json.loads((output / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(index["metric_gates"]["status"], "passed")
            for entry in index["models"][:2]:
                self.assertEqual(entry["report_source"], "single")
                self.assertNotIn("--compare", entry["replay_command"])
                self.assertIsNone(entry["metric_gates"]["checks"][0]["baseline"])

    def test_batch_invalid_configuration_input_and_limits_do_not_commit_a_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            for flags in [["--min-metric", "ap=NaN"], ["--min-class-metric", "999:ap=0"],
                          ["--undefined-gate", "skip"], ["--min-class-metric", "-7:ap=0"]]:
                output = folder / "bundle"
                result = self.batch(output, *flags)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(output.exists())
            bad = folder / "bad.json"
            bad.write_text("{", encoding="utf-8")
            output = folder / "bad-input"
            result = self.batch(output, "--min-metric", "ap50=0.5", invalid=bad)
            self.assertEqual(result.returncode, 2)
            self.assertFalse(output.exists())
            size = len(self.run_cli(paired=False).stdout.encode("utf-8")) + 100
            limited = folder / "limited"
            result = self.batch(limited, "--max-metric-drop", "ap=0.1", "--max-report-bytes", size)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertFalse(limited.exists())

    def test_warning_gate_remains_independent_of_metric_gate_result(self):
        with tempfile.TemporaryDirectory() as directory:
            predictions = json.loads(BASE.read_text(encoding="utf-8"))
            predictions[0]["bbox"] = [-10, -10, 20, 20]
            source = Path(directory) / "outside.json"
            source.write_text(json.dumps(predictions), encoding="utf-8")
            result = self.run_cli("--min-metric", "ap=0", "--fail-on-warning", paired=False, prediction=source)
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual(json.loads(result.stdout)["metric_gates"]["status"], "passed")
            self.assertIn("warning", result.stderr)


if __name__ == "__main__":
    unittest.main()
