"""Verify a candidate archive without linking to the source checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def verify(archive, destination, expected_version):
    destination.mkdir(parents=True, exist_ok=False)
    module, consumer = destination / "module", destination / "consumer"
    module.mkdir()
    with ZipFile(archive) as zipped:
        for name in zipped.namelist():
            if name.startswith("/") or ".." in Path(name).parts:
                raise ValueError("Unsafe archive entry")
        names = set(zipped.namelist())
        assert not any(name.startswith(("site/", "viewer/", "examples/")) for name in names)
        assert not any("__pycache__" in name.split("/") or name.endswith((".pyc", ".pyo")) for name in names)
        assert {"moon.mod", "mask_polygon.mbt", "mask_evaluation.mbt", "quality_gate.mbt", "THIRD_PARTY_NOTICES.md"} <= names
        zipped.extractall(module)
    assert f'version = "{expected_version}"' in (module / "moon.mod").read_text(encoding="utf-8")
    consumer.mkdir()
    for name in ("moon.mod", "moon.pkg", "consumer_test.mbt", "mbmot_adapter.mbt",
                 "geometry_adapter.mbt", "geometry_adapter_test.mbt", "mask_consumer_test.mbt", "gate_consumer_test.mbt"):
        shutil.copyfile(HERE / name, consumer / name)
    (consumer / "moon.work").write_text('members = [".", "../module"]\n', encoding="utf-8")
    checks = []

    def command(cwd, args, expected=0):
        result = subprocess.run(list(map(str, args)), cwd=cwd, text=True, encoding="utf-8", errors="replace", capture_output=True)
        checks.append({"command": list(map(str, args)), "cwd": str(cwd), "exit_code": result.returncode,
                       "stdout": result.stdout, "stderr": result.stderr})
        if result.returncode != expected:
            raise RuntimeError(" ".join(map(str, args)) + "\n" + result.stdout + result.stderr)
        return result.stdout

    try:
        command(module, ["moon", "check", "--target", "all", "--deny-warn"])
        command(module, ["moon", "test", "--target", "all", "--deny-warn"])
        command(consumer, ["moon", "check", "--target", "all", "--deny-warn"])
        command(consumer, ["moon", "test", "--target", "all", "--deny-warn"])
        fixtures = destination / "fixtures"
        fixtures.mkdir()
        for name in ("mask-ground-truth.json", "mask-baseline.json", "mask-candidate.json", "polygon-detections.json"):
            shutil.copyfile(ROOT / "examples" / name, fixtures / name)
        flags = ["--diagnostics", "--image-ranking", "--pr-curves"]
        paired = json.loads(command(module, ["moon", "run", "cli", "--target", "native", "--", fixtures / "mask-ground-truth.json",
                                            fixtures / "mask-baseline.json", "--iou-type", "segm", "--compare", fixtures / "mask-candidate.json", *flags]))
        assert paired["baseline"]["evaluator_version"] == paired["candidate"]["evaluator_version"] == expected_version
        assert paired["baseline"]["summary"]["ap"] == 0 and paired["candidate"]["summary"]["ap"] == 1
        command(module, ["moon", "build", "cli", "--target", "native", "--release"])
        executable = module / "_build/native/release/build/cli/cli.exe"
        if not executable.exists():
            executable = executable.with_name("cli")
        gated = json.loads(command(module, [executable, fixtures / "mask-ground-truth.json", fixtures / "mask-candidate.json",
                                           "--iou-type", "segm", "--compare", fixtures / "mask-baseline.json",
                                           "--max-metric-drop", "ap=0"], expected=3))
        assert gated["metric_gates"]["status"] == "failed" and gated["metric_gates"]["checks"][0]["drop"] == 1
        output = destination / "batch"
        command(module, [sys.executable, ROOT / "examples/batch_eval.py", "--cli", executable,
                         "--ground-truth", fixtures / "mask-ground-truth.json", "--iou-type", "segm", "--baseline", "baseline",
                         "--model", "baseline", fixtures / "mask-baseline.json", "--model", "candidate", fixtures / "mask-candidate.json",
                         "--model", "polygon", fixtures / "polygon-detections.json", "--output-dir", output,
                         "--min-metric", "ap=1", "--max-metric-drop", "ap=0", *flags])
        index = json.loads((output / "index.json").read_text(encoding="utf-8"))
        assert index["format_version"] == "2" and index["iou_type"] == "segm" and index["evaluator_version"] == expected_version
        assert [item["summary"]["ap"] for item in index["models"]] == [0, 1, 1]
        assert index["metric_gates"]["status"] == "passed" and index["metric_gates"]["checked_models"] == 2
        status = "passed"
    except Exception:
        status = "failed"
        raise
    finally:
        result = {"status": status, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                  "expected_version": expected_version, "source_workspace_used": False, "checks": checks}
        (destination / "results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": status, "version": expected_version, "mask_AP": [0, 1, 1], "source_workspace_used": False}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--expected-version", default="0.2.0")
    args = parser.parse_args()
    if args.output_dir:
        verify(args.archive.resolve(), args.output_dir.resolve(), args.expected_version)
    else:
        with tempfile.TemporaryDirectory(prefix="moondeteval-candidate-") as folder:
            verify(args.archive.resolve(), Path(folder) / "verification", args.expected_version)
