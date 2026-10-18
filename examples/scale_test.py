"""Exact native and batch parity across bounded mask overlap caches."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from examples import batch_eval

ROOT = Path(__file__).resolve().parents[1]


class ScaleTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["moon", "build", "cli", "--target", "native", "--release"], cwd=ROOT, check=True, capture_output=True)
        folder = ROOT / "_build/native/release/build/cli"
        cls.cli = next(folder / name for name in ("cli.exe", "cli") if (folder / name).is_file())

    def native(self, *flags):
        return subprocess.run([str(self.cli), str(ROOT / "examples/mask-ground-truth.json"),
                               str(ROOT / "examples/mask-candidate.json"), "--iou-type", "segm",
                               *map(str, flags)], cwd=ROOT, capture_output=True, encoding="utf-8")

    def test_exact_full_reports_for_rle_polygon_comparison_and_gates(self):
        for options, expected in [([], 0), (["--compare", ROOT / "examples/polygon-detections.json"], 0),
                                   (["--compare", ROOT / "examples/mask-baseline.json", "--max-metric-drop", "ap=0"], 3)]:
            flags = ["--diagnostics", "--image-ranking", "--pr-curves", *options]
            reference = self.native(*flags, "--max-iou-cache-pairs", 0)
            self.assertEqual(reference.returncode, expected, reference.stderr)
            for budget in (None, 1, 262144, 16777216):
                result = self.native(*flags, *([] if budget is None else ["--max-iou-cache-pairs", budget]))
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual(result.stdout, reference.stdout)

    def test_invalid_limits_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "report.json"
            for value in ("-1", "16777217", "1.5", "NaN", "2147483648"):
                result = self.native("--max-iou-cache-pairs", value, "--output", output)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(output.exists())
            self.assertEqual(self.native("--max-iou-cache-pairs").returncode, 2)
            self.assertEqual(self.native("--max-iou-cache-pairs", 0, "--max-iou-cache-pairs", 0).returncode, 2)
            output.write_text("preserve", encoding="utf-8")
            self.assertEqual(self.native("--max-iou-cache-pairs", 0, "--output", output).returncode, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "preserve")

    def test_batch_propagates_zero_budget_including_drop_comparisons(self):
        with tempfile.TemporaryDirectory() as folder:
            for gates in ([], ["--max-metric-drop", "ap=0"]):
                output = Path(folder) / ("paired" if gates else "single")
                args = batch_eval.parse_args(["--cli", str(self.cli), "--ground-truth", str(ROOT / "examples/mask-ground-truth.json"),
                    "--baseline", "base", "--model", "base", str(ROOT / "examples/mask-candidate.json"),
                    "--model", "bad", str(ROOT / "examples/mask-baseline.json"), "--iou-type", "segm",
                    "--max-iou-cache-pairs", "0", "--output-dir", str(output), *gates])
                self.assertEqual(batch_eval.run_batch(args), output)
                index = json.loads((output / "index.json").read_text(encoding="utf-8"))
                for item in index["models"]:
                    command = item["replay_command"]
                    self.assertEqual(command[command.index("--max-iou-cache-pairs") + 1], "0")
                    result = subprocess.run(command, cwd=ROOT, capture_output=True, encoding="utf-8")
                    self.assertEqual(result.returncode, 3 if gates and item["name"] == "bad" else 0, result.stderr)
                    replay = json.loads(result.stdout)
                    saved = json.loads((output / item["report_file"]).read_text(encoding="utf-8"))
                    if gates and item["name"] == "bad":
                        self.assertEqual(saved.pop("metric_gates"), replay["metric_gates"])
                        replay = replay["candidate"]
                    self.assertEqual(saved, replay)

    def test_invalid_batch_budget_commits_no_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            for value in (-1, 16777217):
                output = Path(folder) / "absent"
                args = batch_eval.parse_args(["--cli", str(self.cli), "--ground-truth", str(ROOT / "examples/mask-ground-truth.json"),
                    "--baseline", "base", "--model", "base", str(ROOT / "examples/mask-candidate.json"),
                    "--model", "bad", str(ROOT / "examples/mask-baseline.json"), "--output-dir", str(output),
                    "--max-iou-cache-pairs", str(value)])
                with self.assertRaises(batch_eval.BatchError):
                    batch_eval.run_batch(args)
                self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
