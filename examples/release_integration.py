"""Verify an exact registry CLI through batch evaluation in an independent folder."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
MODELS = ("baseline", "candidate", "unchanged")
FIXTURES = (
    "compare-ground-truth.json", "compare-baseline.json", "compare-candidate.json",
    "mask-ground-truth.json", "mask-candidate.json", "mask-baseline.json",
    "polygon-detections.json",
)


class IntegrationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise IntegrationError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def outside_checkout(path):
    try:
        path.relative_to(ROOT)
    except ValueError:
        return True
    return False


def verify(output, version):
    output.mkdir(parents=True, exist_ok=False)
    work = output / "工作目录 中文 空格"
    work.mkdir()
    examples = work / "examples"
    examples.mkdir()
    binary_dir = work / "bin"
    result = {
        "status": "running", "version": version,
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "working_directory": str(work), "batches": {}, "checks": [],
        "runner_sha256": digest(Path(__file__).resolve()),
        "source_cli_fallback": False,
    }
    environment = dict(os.environ, PYTHONIOENCODING="utf-8")

    def command(arguments, expected=0, keep_stdout=False):
        arguments = list(map(str, arguments))
        started = time.monotonic()
        completed = subprocess.run(arguments, cwd=work, env=environment,
                                   capture_output=True, timeout=600)
        record = {
            "command": arguments, "cwd": str(work),
            "expected_exit_code": expected, "exit_code": completed.returncode,
            "seconds": round(time.monotonic() - started, 3),
            "stdout_bytes": len(completed.stdout),
            "stdout_sha256": hashlib.sha256(completed.stdout).hexdigest(),
            "stderr": completed.stderr.decode("utf-8", errors="replace"),
        }
        if keep_stdout:
            record["stdout"] = completed.stdout.decode("utf-8", errors="replace")
        result["checks"].append(record)
        require(completed.returncode == expected,
                f"Expected exit {expected}, received {completed.returncode}: "
                + " ".join(arguments) + "\n" + record["stderr"])
        return completed.stdout

    try:
        require(shutil.which("moon") is not None, "moon must be on PATH")
        require(not (work / "moon.mod").exists() and not (work / "moon.work").exists(),
                "Installation directory must not contain a MoonBit module or workspace")
        source = f"python123-ops/moondeteval/cli@{version}"
        result["toolchain"] = command(["moon", "version", "--all", "--no-path"], keep_stdout=True).decode("utf-8", errors="replace")
        command(["moon", "install", source, "--bin", binary_dir], keep_stdout=True)
        binaries = [path for path in (binary_dir / "cli.exe", binary_dir / "cli") if path.is_file()]
        require(len(binaries) == 1, "Registry installation must produce exactly one native CLI")
        cli = binaries[0].resolve()
        result["cli"] = {
            "source": "registry", "package": source, "path": str(cli),
            "sha256": digest(cli), "install_cwd_has_source_module": False,
            "fresh_bin_directory": True,
        }
        require(cli.parent == binary_dir.resolve(), "Installed CLI is outside the requested bin directory")

        copied = {}
        for name in ("batch_eval.py", *FIXTURES):
            original = ROOT / "examples" / name
            destination = examples / name
            shutil.copyfile(original, destination)
            require(digest(original) == digest(destination), f"Copy differs: {name}")
            copied[name] = digest(destination)
        result["copied_source_sha256"] = copied
        batch = examples / "batch_eval.py"
        flags = ["--diagnostics", "--image-ranking", "--pr-curves"]
        invalid = examples / "invalid-predictions.json"
        invalid.write_text("{", encoding="utf-8")

        for mode, truth_name, predictions, metric, expected_values in (
            ("bbox", "compare-ground-truth.json",
             ("compare-baseline.json", "compare-candidate.json", "compare-baseline.json"),
             "ap50", (1.0, 0.25, 1.0)),
            ("segm", "mask-ground-truth.json",
             ("mask-candidate.json", "mask-baseline.json", "polygon-detections.json"),
             "ap", (1.0, 0.0, 1.0)),
        ):
            truth = examples / truth_name
            bundle = work / (mode + "-batch")
            arguments = [sys.executable, batch, "--cli", cli, "--ground-truth", truth,
                         "--iou-type", mode, "--baseline", "baseline", "--output-dir", bundle,
                         "--max-metric-drop", metric + "=0.1", *flags]
            for name, prediction in zip(MODELS, predictions):
                arguments += ["--model", name, examples / prediction]
            command(arguments, expected=3)
            result["batches"][mode] = str(bundle)
            index = json.loads((bundle / "index.json").read_text(encoding="utf-8"))
            require(index["format_version"] == "2" and index["iou_type"] == mode,
                    f"Incorrect batch format or task: {mode}")
            require(index["evaluator_version"] == version, f"Incorrect evaluator version: {mode}")
            require(index["baseline"] == "baseline" and [entry["name"] for entry in index["models"]] == list(MODELS),
                    f"Missing or reordered models: {mode}")
            require(index["ground_truth_sha256"] == digest(truth), f"Ground-truth hash differs: {mode}")
            require(index["metric_gates"]["status"] == "failed"
                    and index["metric_gates"]["failed_models"] == ["candidate"]
                    and index["metric_gates"]["checked_models"] == 2,
                    f"Incorrect aggregate gate result: {mode}")
            require({path.name for path in bundle.iterdir()} == {"index.json", *(name + ".report.json" for name in MODELS)},
                    f"Incomplete or unexpected batch files: {mode}")
            for entry, prediction, expected_value in zip(index["models"], predictions, expected_values):
                report_path = bundle / entry["report_file"]
                report = json.loads(report_path.read_text(encoding="utf-8"))
                require(report["schema_version"] == "0.1.0" and report["evaluator_version"] == version,
                        f"Incorrect report version: {mode}/{entry['name']}")
                require(report.get("iou_type", "bbox") == mode, f"Incorrect report task: {mode}/{entry['name']}")
                require(report["summary"][metric] == expected_value, f"Unexpected {metric}: {mode}/{entry['name']}")
                require(report["summary"] == entry["summary"] and report["counts"] == entry["counts"],
                        f"Index/report values differ: {mode}/{entry['name']}")
                require(report["classes"] and report["diagnostics"] and report["image_summaries"] and report["pr_curves"],
                        f"Full report sections are absent: {mode}/{entry['name']}")
                require(entry["report_sha256"] == digest(report_path)
                        and entry["prediction_sha256"] == digest(examples / prediction),
                        f"Report or input hash differs: {mode}/{entry['name']}")
                expected_status = "failed" if entry["name"] == "candidate" else "passed"
                replay = entry["replay_command"]
                require(Path(replay[0]).resolve() == cli, "Replay command did not use the installed registry CLI")
                replay_report = json.loads(command(replay, expected=3 if expected_status == "failed" else 0))
                if entry["name"] == "baseline":
                    require("metric_gates" not in entry and "metric_gates" not in report,
                            "Baseline must remain an unchecked reference")
                else:
                    gates = report["metric_gates"]
                    require(gates == entry["metric_gates"] and gates["status"] == expected_status,
                            f"Incorrect native gate outcome: {mode}/{entry['name']}")
                    require(len(gates["checks"]) == 1 and gates["checks"][0]["metric"] == metric,
                            f"Incorrect native gate rule: {mode}/{entry['name']}")
                    if expected_status == "failed":
                        require(gates["checks"][0]["reason"] == "drop_exceeded",
                                f"Incorrect native failure reason: {mode}")
                    require(entry["report_source"] == "comparison.candidate", "Drop gate must use native comparison")
                    require(replay_report["metric_gates"] == gates, "Replayed native gates differ")
                    replay_report = dict(replay_report["candidate"], metric_gates=replay_report["metric_gates"])
                require(report == replay_report, f"Complete report replay differs: {mode}/{entry['name']}")

            before = {path.name: digest(path) for path in bundle.iterdir()}
            command(arguments, expected=2)
            require({path.name: digest(path) for path in bundle.iterdir()} == before,
                    f"Existing batch was overwritten: {mode}")
            bad_output = work / (mode + "-invalid-batch")
            bad_arguments = list(arguments)
            bad_arguments[bad_arguments.index("--output-dir") + 1] = bad_output
            command([*bad_arguments, "--model", "invalid", invalid], expected=2)
            require(not bad_output.exists(), f"Invalid input committed a partial batch: {mode}")
            bad_report = work / (mode + "-invalid.report.json")
            command([cli, truth, invalid, "--iou-type", mode, "--output", bad_report], expected=2)
            require(not bad_report.exists(), f"Invalid input committed a native report: {mode}")
            existing = bundle / "baseline.report.json"
            command([cli, truth, examples / predictions[0], "--iou-type", mode, "--output", existing], expected=2)
            require(digest(existing) == before[existing.name], f"Existing native report was overwritten: {mode}")
            result.setdefault("batch_results", {})[mode] = {
                "exit_code": 3, "metric": metric, "values": dict(zip(MODELS, expected_values)),
                "gate_states": {"baseline": "reference", "candidate": "failed", "unchanged": "passed"},
                "full_replay_equal": True, "hashes_verified": True,
                "invalid_input_exit_code": 2, "existing_output_preserved": True,
            }
        require(not list(work.glob(".moondeteval-batch-*")), "Batch staging directories were left behind")
        result["status"] = "passed"
    except Exception as error:
        result["status"] = "failed"
        result["error"] = str(error)
        raise
    finally:
        result["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
        (output / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "version": version,
                      "result": str(output / "result.json"), "batches": result["batches"]}, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True,
                        help="new absolute directory outside this checkout; preserves reports and result.json")
    parser.add_argument("--version", default="0.2.0", help="exact published version (default: 0.2.0)")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version):
        parser.error("--version requires an exact numeric release version")
    output = args.output_dir.resolve()
    if not args.output_dir.is_absolute() or not outside_checkout(output):
        parser.error("--output-dir must be an absolute path outside this checkout")
    if output.exists():
        parser.error("--output-dir already exists")
    try:
        verify(output, args.version)
    except (IntegrationError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"release integration: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
