"""Evaluate named COCO bbox or segmentation predictors on one fixed dataset."""

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
METRICS = (
    "ap", "ap50", "ap75", "ap_small", "ap_medium", "ap_large",
    "ar1", "ar10", "ar100", "ar_small", "ar_medium", "ar_large",
)
NAME = re.compile(r"[A-Za-z0-9_-]+\Z")
WINDOWS_RESERVED = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
GATE_OPTIONS = ("--min-metric", "--max-metric-drop", "--min-class-metric", "--max-class-drop")


class BatchError(Exception):
    pass


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def input_path(value):
    path = Path(value).resolve()
    if not path.is_file():
        raise BatchError(f"input is not a file: {path}")
    return path


def snapshot(source, target):
    before = digest(source)
    shutil.copyfile(source, target)
    after = digest(source)
    copied = digest(target)
    if before != after or after != copied:
        raise BatchError(f"input changed while being copied: {source}")
    return copied


def checked_report(path, expected_iou_type="bbox", report=None):
    if report is None:
        try:
            report = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise BatchError(f"invalid CLI report {path.name}: {error}") from error
    if not isinstance(report, dict) or report.get("schema_version") != "0.1.0":
        raise BatchError(f"unsupported CLI report schema: {path.name}")
    if not isinstance(report.get("config"), dict) or not isinstance(report.get("counts"), dict):
        raise BatchError(f"report lacks config or counts: {path.name}")
    # The published bbox CLI omits the marker; segm must be explicit.
    actual_iou_type = report.get("iou_type", "bbox")
    if actual_iou_type not in ("bbox", "segm") or actual_iou_type != expected_iou_type:
        raise BatchError(f"report iou_type={actual_iou_type!r} differs from requested {expected_iou_type}: {path.name}")
    policy = report["config"].get("ignore_policy")
    if (actual_iou_type == "bbox" and policy == "coco_segm") or (actual_iou_type == "segm" and policy == "coco_bbox"):
        raise BatchError(f"report ignore policy disagrees with iou_type: {path.name}")
    summary = report.get("summary")
    if not isinstance(summary, dict):
        raise BatchError(f"report lacks summary: {path.name}")
    for key in METRICS:
        value = summary.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            raise BatchError(f"invalid {key} in report: {path.name}")
        if value != -1 and not 0 <= value <= 1:
            raise BatchError(f"out-of-range {key} in report: {path.name}")
    return report


def checked_gates(value, exit_code):
    if not isinstance(value, dict) or value.get("format_version") != "1" or value.get("status") not in ("passed", "failed"):
        raise BatchError("CLI did not provide a supported metric_gates result; use the current source CLI")
    if value.get("undefined_policy") not in ("fail", "skip") or not isinstance(value.get("checks"), list) or not 1 <= len(value["checks"]) <= 1000:
        raise BatchError("invalid metric gate policy/result")
    if value["status"] != ("failed" if exit_code == 3 else "passed"):
        raise BatchError("CLI exit code disagrees with metric gates")
    for check in value["checks"]:
        if not isinstance(check, dict) or check.get("kind") not in ("minimum", "max_drop") or check.get("metric") not in METRICS or check.get("status") not in ("passed", "failed", "skipped"):
            raise BatchError("invalid metric gate check")
    return value


class GateArgument(argparse.Action):
    def __call__(self, parser, namespace, values, option_string=None):
        rules = getattr(namespace, "gate_options", None)
        if rules is None:
            rules = []
        rules.append((option_string, values))
        namespace.gate_options = rules


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ground-truth", required=True, type=input_path)
    parser.add_argument("--model", nargs=2, action="append", metavar=("NAME", "PREDICTIONS"), required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--cli", type=input_path, help="native MoonDetEval executable; default: moon run cli")
    parser.add_argument("--iou-type", choices=("bbox", "segm"), default="bbox",
                        help="one evaluation geometry for all models (default: bbox)")
    for flag in ("diagnostics", "image-ranking", "pr-curves"):
        parser.add_argument("--" + flag, action="store_true")
    for flag in ("max-input-bytes", "max-total-input-bytes", "max-records", "max-diagnostics", "max-report-bytes"):
        parser.add_argument("--" + flag, type=int)
    for flag in GATE_OPTIONS:
        parser.add_argument(flag, action=GateArgument, dest="gate_options")
    parser.add_argument("--undefined-gate", choices=("fail", "skip"))
    # argparse otherwise treats a signed CATEGORY:METRIC=VALUE as an option.
    original = list(sys.argv[1:] if argv is None else argv)
    normalized = []
    position = 0
    while position < len(original):
        if original[position] in GATE_OPTIONS and position + 1 < len(original) and original[position + 1].startswith("-") and not original[position + 1].startswith("--"):
            normalized.append(original[position] + "=" + original[position + 1])
            position += 2
        else:
            normalized.append(original[position])
            position += 1
    return parser.parse_args(normalized)


def run_batch(args):
    gate_options = args.gate_options or []
    if len(gate_options) > 1000 or (args.undefined_gate is not None and not gate_options):
        raise BatchError("metric gates require 1 to 1000 rules; --undefined-gate requires rules")
    gate_flags = [item for pair in gate_options for item in pair]
    if args.undefined_gate is not None:
        gate_flags += ["--undefined-gate", args.undefined_gate]
    has_drop = any(flag in ("--max-metric-drop", "--max-class-drop") for flag, _ in gate_options)
    if len(args.model) < 2:
        raise BatchError("at least two --model NAME PATH entries are required")
    names = [name for name, _ in args.model]
    if any(not NAME.fullmatch(name) for name in names):
        raise BatchError("model names must contain only ASCII letters, digits, _ or -")
    if len({name.casefold() for name in names}) != len(names):
        raise BatchError("model names must be unique ignoring case")
    if any(name.upper() in WINDOWS_RESERVED for name in names):
        raise BatchError("model names cannot use Windows device names")
    if args.baseline not in names:
        raise BatchError("--baseline must name one of the models")
    models = [(name, input_path(file)) for name, file in args.model]
    output = args.output_dir.resolve()
    if output.exists():
        raise BatchError(f"output directory already exists: {output}")
    if not output.parent.is_dir():
        raise BatchError(f"output parent directory does not exist: {output.parent}")
    if args.cli is None and shutil.which("moon") is None:
        raise BatchError("moon CLI is not on PATH; pass --cli PATH")
    for flag in ("max_input_bytes", "max_total_input_bytes", "max_records", "max_diagnostics", "max_report_bytes"):
        value = getattr(args, flag)
        if value is not None and value <= 0:
            raise BatchError(f"--{flag.replace('_', '-')} requires a positive integer")

    prefix = [str(args.cli)] if args.cli else ["moon", "run", "cli", "--target", "native", "--"]
    # Omit the default bbox flag so older registry-installed bbox CLIs still work.
    flags = ["--iou-type", "segm"] if args.iou_type == "segm" else []
    flags += ["--" + key.replace("_", "-") for key in ("diagnostics", "image_ranking", "pr_curves") if getattr(args, key)]
    for key in ("max_input_bytes", "max_total_input_bytes", "max_records", "max_diagnostics", "max_report_bytes"):
        value = getattr(args, key)
        if value is not None:
            flags.extend(("--" + key.replace("_", "-"), str(value)))

    with tempfile.TemporaryDirectory(prefix=".moondeteval-batch-", dir=output.parent) as temporary:
        temporary = Path(temporary)
        frozen = temporary / "inputs"
        frozen.mkdir()
        stage = temporary / "bundle"
        stage.mkdir()
        ground_hash = snapshot(args.ground_truth, frozen / "ground-truth.json")
        model_inputs = []
        for name, source in models:
            model_inputs.append((name, source, frozen / f"{name}.json", snapshot(source, frozen / f"{name}.json")))

        entries = []
        common_config = None
        common_truth_counts = None
        evaluator_version = None
        common_gates = None
        baseline_input = next(item for item in model_inputs if item[0] == args.baseline)
        ordered_inputs = sorted(model_inputs, key=lambda item: item[0] != args.baseline) if gate_options else model_inputs
        for name, source, frozen_source, source_hash in ordered_inputs:
            report_name = f"{name}.report.json"
            report_path = stage / report_name
            gated = bool(gate_options) and name != args.baseline
            paired = gated and has_drop
            cli_output = temporary / (name + ".paired.json") if paired else report_path
            input_args = [str(frozen / "ground-truth.json"), str(baseline_input[2] if paired else frozen_source)]
            compare_args = ["--compare", str(frozen_source)] if paired else []
            command = prefix + input_args + flags + compare_args + (gate_flags if gated else []) + ["--output", str(cli_output)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
            if result.returncode not in ((0, 3) if gated else (0,)):
                raise BatchError(f"{name}: MoonDetEval CLI exited {result.returncode}: {result.stderr.strip()}")
            if paired:
                try:
                    comparison = json.loads(cli_output.read_text(encoding="utf-8"))
                except (OSError, UnicodeError, json.JSONDecodeError) as error:
                    raise BatchError(f"invalid comparison for {name}: {error}") from error
                if not isinstance(comparison, dict) or comparison.get("schema_version") != "0.1.0":
                    raise BatchError("invalid comparison schema")
                before = checked_report(cli_output, args.iou_type, comparison.get("baseline", {}))
                expected_base = next(entry for entry in entries if entry["name"] == args.baseline)
                if before["summary"] != expected_base["summary"] or before["counts"] != expected_base["counts"] or before["config"] != common_config or before.get("evaluator_version") != evaluator_version:
                    raise BatchError(f"{name}: comparison baseline differs from the frozen baseline")
                report = checked_report(cli_output, args.iou_type, comparison.get("candidate", {}))
                report["metric_gates"] = checked_gates(comparison.get("metric_gates"), result.returncode)
                report_path.write_text(json.dumps(report, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
            else:
                report = checked_report(report_path, args.iou_type)
                if gated:
                    checked_gates(report.get("metric_gates"), result.returncode)
            config = report["config"]
            truth_counts = {key: report["counts"].get(key) for key in ("images", "categories", "ground_truths")}
            version = report.get("evaluator_version")
            if common_config is None:
                common_config, common_truth_counts, evaluator_version = config, truth_counts, version
            elif config != common_config or truth_counts != common_truth_counts or version != evaluator_version:
                raise BatchError(f"{name}: report configuration, dataset counts or evaluator version differs")
            entry = {
                "name": name,
                "iou_type": args.iou_type,
                "prediction_path": str(source),
                "prediction_sha256": source_hash,
                "report_file": report_name,
                "report_sha256": digest(report_path),
                "counts": report["counts"],
                "summary": {metric: report["summary"][metric] for metric in METRICS},
                "replay_command": prefix + [str(args.ground_truth), str(baseline_input[1] if paired else source)] + flags + (["--compare", str(source)] if paired else []) + (gate_flags if gated else []),
            }
            if gated:
                signature = {"undefined_policy": report["metric_gates"]["undefined_policy"],
                             "rules": [{key: row.get(key) for key in ("kind", "metric", "category_id", "threshold")} for row in report["metric_gates"]["checks"]]}
                if common_gates is None:
                    common_gates = signature
                elif signature != common_gates:
                    raise BatchError(f"{name}: metric gate policy differs across models")
                entry["metric_gates"] = report["metric_gates"]
                entry["report_source"] = "comparison.candidate" if paired else "single"
            entries.append(entry)

        by_name = {entry["name"]: entry for entry in entries}
        entries = [by_name[name] for name in names]

        baseline = next(item for item in entries if item["name"] == args.baseline)
        for item in entries:
            item["delta_from_baseline"] = {
                metric: None if item["summary"][metric] == -1 or baseline["summary"][metric] == -1
                else item["summary"][metric] - baseline["summary"][metric]
                for metric in METRICS
            }
        if digest(args.ground_truth) != ground_hash:
            raise BatchError("ground truth changed during evaluation")
        for name, source, _, source_hash in model_inputs:
            if digest(source) != source_hash:
                raise BatchError(f"{name}: predictions changed during evaluation")
        index = {
            "format_version": "2",
            "iou_type": args.iou_type,
            "created_at_utc": datetime.now(timezone.utc).isoformat(),
            "working_directory": str(ROOT),
            "ground_truth_path": str(args.ground_truth),
            "ground_truth_sha256": ground_hash,
            "evaluator_version": evaluator_version,
            "config": common_config,
            "ground_truth_counts": common_truth_counts,
            "baseline": args.baseline,
            "models": entries,
        }
        if gate_options:
            checked_models = [entry for entry in entries if entry["name"] != args.baseline]
            failed = [entry["name"] for entry in checked_models if entry["metric_gates"]["status"] == "failed"]
            index["metric_gates"] = {
                "format_version": "1", "status": "failed" if failed else "passed",
                "checked_models": len(checked_models), "failed_models": failed,
                "undefined_policy": checked_models[0]["metric_gates"]["undefined_policy"],
                "rules": [{key: row[key] for key in ("kind", "metric", "category_id", "threshold")} for row in checked_models[0]["metric_gates"]["checks"]],
            }
        (stage / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if output.exists():
            raise BatchError(f"output directory appeared during evaluation: {output}")
        os.rename(stage, output)
    return output


def main(argv=None):
    try:
        result = run_batch(parse_args(argv))
    except BatchError as error:
        print(f"batch evaluation: {error}", file=sys.stderr)
        return 2
    print(result / "index.json")
    index = json.loads((result / "index.json").read_text(encoding="utf-8"))
    if index.get("metric_gates", {}).get("status") == "failed":
        print("metric gates failed: " + ", ".join(index["metric_gates"]["failed_models"]), file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
