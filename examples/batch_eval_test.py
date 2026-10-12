"""Integration checks for the source-checkout batch evaluator."""

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "examples/batch_eval.py"
SPEC = importlib.util.spec_from_file_location("moondeteval_batch_eval", SCRIPT)
batch_eval = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(batch_eval)
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
            self.assertEqual(index["format_version"], "2")
            self.assertEqual(index["iou_type"], "bbox")
            self.assertEqual(len(index["models"]), 2)
            direct = subprocess.run(
                ["moon", "run", "cli", "--target", "native", "--", str(TRUTH), str(BASE),
                 "--compare", str(CANDIDATE), "--diagnostics", "--image-ranking", "--pr-curves"],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            self.assertEqual(direct.returncode, 0, direct.stderr)
            paired = json.loads(direct.stdout)
            for entry, side in zip(index["models"], ("baseline", "candidate")):
                self.assertEqual(entry["iou_type"], "bbox")
                self.assertNotIn("--iou-type", entry["replay_command"])
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

    def test_segm_three_inputs_match_pairwise_reports_and_replay(self):
        truth = ROOT / "examples/polygon-ground-truth.json"
        polygon = ROOT / "examples/polygon-detections.json"
        rle = ROOT / "examples/mask-candidate.json"
        bad = ROOT / "examples/mask-baseline.json"
        flags = ["--diagnostics", "--image-ranking", "--pr-curves"]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "segm"
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--ground-truth", str(truth), "--iou-type", "segm",
                 "--model", "polygon", str(polygon), "--model", "rle", str(rle),
                 "--model", "bad", str(bad), "--baseline", "polygon", "--output-dir", str(output), *flags],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(result.returncode, 0, result.stderr)
            index = json.loads((output / "index.json").read_text(encoding="utf-8"))
            self.assertEqual((index["format_version"], index["iou_type"]), ("2", "segm"))
            self.assertEqual(index["config"]["ignore_policy"], "coco_segm")
            paired_run = subprocess.run(
                ["moon", "run", "cli", "--target", "native", "--", str(truth), str(polygon),
                 "--compare", str(bad), "--iou-type", "segm", *flags],
                cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True)
            paired = json.loads(paired_run.stdout)
            for index_position, entry in enumerate(index["models"]):
                report_path = output / entry["report_file"]
                report = json.loads(report_path.read_text(encoding="utf-8"))
                side = "candidate" if index_position == 2 else "baseline"
                self.assertEqual(report, paired[side])
                self.assertEqual(entry["iou_type"], "segm")
                self.assertEqual(entry["report_sha256"], hashlib.sha256(report_path.read_bytes()).hexdigest())
                self.assertEqual(entry["prediction_sha256"], hashlib.sha256(Path(entry["prediction_path"]).read_bytes()).hexdigest())
                self.assertEqual(entry["delta_from_baseline"]["ap"], -1 if index_position == 2 else 0)
                self.assertIsNone(entry["delta_from_baseline"]["ap_medium"])
                replay = subprocess.run(entry["replay_command"], cwd=index["working_directory"],
                                        capture_output=True, text=True, encoding="utf-8", check=True)
                self.assertEqual(json.loads(replay.stdout), report)
                position = entry["replay_command"].index("--iou-type")
                self.assertEqual(entry["replay_command"][position + 1], "segm")

    def test_segm_bad_polygon_and_invalid_mode_leave_no_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory)
            malformed = parent / "malformed.json"
            malformed.write_text('[{"image_id":1,"category_id":1,"score":1,"segmentation":[[0,0,1]]}]', encoding="utf-8")
            output = parent / "bundle"
            command = [sys.executable, str(SCRIPT), "--ground-truth", str(ROOT / "examples/polygon-ground-truth.json"),
                       "--model", "good", str(ROOT / "examples/polygon-detections.json"),
                       "--model", "bad", str(malformed), "--baseline", "good", "--output-dir", str(output)]
            for mode in ("segm", "oks"):
                result = subprocess.run(command + ["--iou-type", mode], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
                self.assertEqual(result.returncode, 2)
                self.assertFalse(output.exists())
            self.assertEqual(list(parent.iterdir()), [malformed])

    def test_wrong_missing_and_unknown_report_types_never_publish_an_index(self):
        # Simulate a custom CLI returning a wrong task while keeping all other
        # configuration/counts identical; a successful process is not enough.
        raw = subprocess.run(
            ["moon", "run", "cli", "--target", "native", "--", str(ROOT / "examples/polygon-ground-truth.json"),
             str(ROOT / "examples/polygon-detections.json"), "--iou-type", "segm"],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", check=True)
        original = json.loads(raw.stdout)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bundle"
            args = batch_eval.parse_args([
                "--ground-truth", str(ROOT / "examples/polygon-ground-truth.json"),
                "--model", "a", str(ROOT / "examples/polygon-detections.json"),
                "--model", "b", str(ROOT / "examples/mask-candidate.json"),
                "--baseline", "a", "--output-dir", str(output), "--iou-type", "segm"])
            for marker in ("bbox", None, "unknown"):
                calls = []

                def wrong_cli(command, **kwargs):
                    report = json.loads(json.dumps(original))
                    if calls:
                        if marker is None:
                            report.pop("iou_type")
                        else:
                            report["iou_type"] = marker
                    calls.append(command)
                    Path(command[command.index("--output") + 1]).write_text(json.dumps(report), encoding="utf-8")
                    return subprocess.CompletedProcess(command, 0, "", "")

                with mock.patch.object(batch_eval.subprocess, "run", side_effect=wrong_cli):
                    with self.assertRaisesRegex(batch_eval.BatchError, "iou_type"):
                        batch_eval.run_batch(args)
                self.assertEqual(len(calls), 2)
                self.assertFalse(output.exists())
                self.assertEqual(list(Path(directory).iterdir()), [])

    def test_report_marker_and_ignore_policy_must_agree(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.json"
            for mode, policy in (("segm", "coco_bbox"), ("bbox", "coco_segm")):
                path.write_text(json.dumps({"schema_version": "0.1.0", "iou_type": mode,
                                            "config": {"ignore_policy": policy}, "counts": {}}), encoding="utf-8")
                with self.assertRaisesRegex(batch_eval.BatchError, "ignore policy"):
                    batch_eval.checked_report(path, mode)

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
