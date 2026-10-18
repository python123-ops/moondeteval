"""Run native policy-file and batch snapshot boundary checks."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from examples import batch_eval

ROOT = Path(__file__).resolve().parents[1]
TRUTH = ROOT / "examples/compare-ground-truth.json"
BASE = ROOT / "examples/compare-baseline.json"
CANDIDATE = ROOT / "examples/compare-candidate.json"


def policy(*rules, **options):
    return {"format_version": "1", "rules": list(rules), **options}


def rule(kind="max_drop", metric="ap50", threshold=.1, **options):
    return {"kind": kind, "metric": metric, "threshold": threshold, **options}


class PolicyFileTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["moon", "build", "cli", "--target", "native", "--release"], cwd=ROOT, check=True, capture_output=True)
        folder = ROOT / "_build/native/release/build/cli"
        cls.cli = next(folder / name for name in ("cli.exe", "cli") if (folder / name).is_file())

    def native(self, *args):
        return subprocess.run([str(self.cli), *map(str, args)], cwd=ROOT, capture_output=True, encoding="utf-8")

    def write(self, folder, value):
        path = Path(folder) / "policy.json"
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return path

    def batch_args(self, output, path):
        return ["--cli", str(self.cli), "--ground-truth", str(TRUTH), "--baseline", "base",
                "--model", "bad", str(CANDIDATE), "--model", "base", str(BASE), "--model", "good", str(BASE),
                "--gate-policy", str(path), "--output-dir", str(output)]

    def test_preflight_without_dataset_and_canonical_round_trip(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule(), rule("minimum", "ar100", 0, category_id=-2147483648)))
            result = self.native("--check-gate-policy", path)
            self.assertEqual(result.returncode, 0, result.stderr)
            canonical = json.loads(result.stdout)
            self.assertEqual(canonical["undefined_policy"], "fail")
            self.assertIsNone(canonical["rules"][0]["category_id"])
            self.assertEqual(canonical["rules"][1]["category_id"], -2147483648)
            path.write_text(result.stdout, encoding="utf-8")
            self.assertEqual(self.native("--check-gate-policy", path).stdout, result.stdout)

    def test_file_and_inline_rules_produce_identical_complete_failure_reports(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule(), rule("minimum", "ar100", .5)))
            output = Path(folder) / "report.json"
            result = self.native(TRUTH, BASE, "--compare", CANDIDATE, "--gate-policy", path, "--output", output)
            inline = self.native(TRUTH, BASE, "--compare", CANDIDATE, "--max-metric-drop", "ap50=0.1", "--min-metric", "ar100=0.5")
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), json.loads(inline.stdout))
            self.assertEqual(json.loads(inline.stdout)["metric_gates"]["checks"][0]["reason"], "drop_exceeded")

    def test_invalid_policies_and_wrong_cli_combinations_never_create_a_report(self):
        invalid = [policy(), policy(rule(), rule()), policy(rule(metric="accuracy")), policy(rule(threshold=-.1)),
                   policy(rule(category_id=1.5)), policy(rule(category_id=True)), policy(rule(category_id=2147483648)),
                   policy(rule(threshold="0.1")), policy(rule(catgory_id=1)), policy(rule(), extra=1),
                   policy(rule(), undefined_policy="ignore"), {"format_version": "2", "rules": [rule()]},
                   policy(*[rule("minimum", category_id=i) for i in range(1001)])]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "output.json"
            for value in invalid:
                path = self.write(folder, value)
                result = self.native("--check-gate-policy", path)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertEqual(result.stdout, "")
            path = self.write(folder, policy(rule()))
            for flags in [["--min-metric", "ap=0"], ["--undefined-gate", "skip"], ["--min-ap50", "0"], ["--gate-policy", path]]:
                result = self.native(TRUTH, BASE, "--compare", CANDIDATE, "--gate-policy", path, *flags, "--output", output)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(output.exists())
            self.assertEqual(self.native(TRUTH, BASE, "--gate-policy", path).returncode, 2)
            self.assertEqual(self.native("--check-gate-policy").returncode, 2)

    def test_file_size_utf8_total_budget_and_existing_output_boundaries(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule("minimum", "ap", 0)))
            raw = path.read_bytes()
            path.write_bytes(raw + b" " * (262144 - len(raw)))
            self.assertEqual(self.native("--check-gate-policy", path).returncode, 0)
            path.write_bytes(path.read_bytes() + b" ")
            self.assertEqual(self.native("--check-gate-policy", path).returncode, 2)
            path.write_bytes(b"\xff")
            self.assertEqual(self.native("--check-gate-policy", path).returncode, 2)
            path.write_bytes(raw)
            total = len(raw) + TRUTH.stat().st_size + BASE.stat().st_size
            self.assertEqual(self.native(TRUTH, BASE, "--gate-policy", path, "--max-total-input-bytes", total).returncode, 0)
            output = Path(folder) / "out.json"
            self.assertEqual(self.native(TRUTH, BASE, "--gate-policy", path, "--max-total-input-bytes", total-1, "--output", output).returncode, 2)
            self.assertFalse(output.exists())
            output.write_text("keep", encoding="utf-8")
            self.assertEqual(self.native(TRUTH, BASE, "--gate-policy", path, "--output", output).returncode, 2)
            self.assertEqual(output.read_text(encoding="utf-8"), "keep")
            path.unlink()
            self.assertEqual(self.native("--check-gate-policy", path).returncode, 2)

    def test_undefined_skip_and_unknown_dataset_category_are_distinct(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule("minimum", "ap_large", 0), undefined_policy="skip"))
            result = self.native(TRUTH, BASE, "--gate-policy", path)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(json.loads(result.stdout)["metric_gates"]["reason"], "all_skipped")
            path = self.write(folder, policy(rule("minimum", "ap", 0, category_id=-7)))
            self.assertEqual(self.native("--check-gate-policy", path).returncode, 0)
            self.assertEqual(self.native(TRUTH, BASE, "--gate-policy", path).returncode, 2)

    def test_batch_persists_exact_shared_snapshot_and_mixed_outcomes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule()))
            output = Path(folder) / "bundle"
            result = subprocess.run([sys.executable, "examples/batch_eval.py", *self.batch_args(output, path)], cwd=ROOT, capture_output=True, encoding="utf-8")
            self.assertEqual(result.returncode, 3, result.stderr)
            index = json.loads((output / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(index["metric_gates"]["failed_models"], ["bad"])
            self.assertEqual((output / "gate-policy.json").read_bytes(), path.read_bytes())
            self.assertEqual(index["gate_policy"]["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())
            self.assertEqual(len(list(output.iterdir())), 5)
            path = self.write(folder, policy(rule("minimum", "ap50", .2)))
            output2 = Path(folder) / "absolute"
            batch_eval.run_batch(batch_eval.parse_args(self.batch_args(output2, path)))
            absolute = json.loads((output2 / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(absolute["metric_gates"]["status"], "passed")
            self.assertEqual(absolute["models"][0]["report_source"], "single")

    def test_batch_rejects_mutated_original_and_frozen_policy_without_partial_output(self):
        real_run = subprocess.run
        for frozen in (False, True):
            with self.subTest(frozen=frozen), tempfile.TemporaryDirectory() as folder:
                path = self.write(folder, policy(rule()))
                output = Path(folder) / "bundle"
                def mutate(argv, **kwargs):
                    result = real_run(argv, **kwargs)
                    if frozen and "--check-gate-policy" in argv:
                        Path(argv[-1]).write_text(json.dumps(policy(rule(threshold=1))), encoding="utf-8")
                    elif not frozen and "--gate-policy" in argv:
                        path.write_text(path.read_text(encoding="utf-8") + " ", encoding="utf-8")
                    return result
                with patch.object(batch_eval.subprocess, "run", side_effect=mutate):
                    with self.assertRaises(batch_eval.BatchError):
                        batch_eval.run_batch(batch_eval.parse_args(self.batch_args(output, path)))
                self.assertFalse(output.exists())

    def test_batch_invalid_file_and_conflicting_rules_fail_before_bundle_commit(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule(catgory_id=1)))
            output = Path(folder) / "bundle"
            self.assertEqual(batch_eval.main(self.batch_args(output, path)), 2)
            path = self.write(folder, policy(rule()))
            self.assertEqual(batch_eval.main(self.batch_args(output, path) + ["--min-metric", "ap=0"]), 2)
            repeated = subprocess.run([sys.executable, "examples/batch_eval.py", *self.batch_args(output, path), "--gate-policy", str(path)],
                                      cwd=ROOT, capture_output=True, encoding="utf-8")
            self.assertEqual(repeated.returncode, 2)
            self.assertIn("only once", repeated.stderr)
            self.assertFalse(output.exists())

    def test_snapshot_changed_while_copying_to_bundle_is_not_published(self):
        real_copy = batch_eval.shutil.copyfile
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule()))
            output = Path(folder) / "bundle"
            def altered(source, target, **kwargs):
                result = real_copy(source, target, **kwargs)
                if Path(target).parent.name == "bundle" and Path(target).name == "gate-policy.json":
                    with Path(target).open("ab") as stream:
                        stream.write(b" ")
                return result
            with patch.object(batch_eval.shutil, "copyfile", side_effect=altered):
                with self.assertRaisesRegex(batch_eval.BatchError, "while being saved"):
                    batch_eval.run_batch(batch_eval.parse_args(self.batch_args(output, path)))
            self.assertFalse(output.exists())

    def test_model_names_cannot_collide_with_frozen_truth_or_policy_files(self):
        with tempfile.TemporaryDirectory() as folder:
            path = self.write(folder, policy(rule()))
            output = Path(folder) / "bundle"
            args = ["--cli", str(self.cli), "--ground-truth", str(TRUTH), "--baseline", "ground-truth",
                    "--model", "ground-truth", str(BASE), "--model", "gate-policy", str(CANDIDATE),
                    "--gate-policy", str(path), "--output-dir", str(output)]
            self.assertEqual(batch_eval.main(args), 3)
            index = json.loads((output / "index.json").read_text(encoding="utf-8"))
            self.assertEqual(index["metric_gates"]["failed_models"], ["gate-policy"])
            self.assertEqual([entry["summary"]["ap50"] for entry in index["models"]], [1, .25])


if __name__ == "__main__":
    unittest.main()
