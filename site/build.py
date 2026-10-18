"""Build a static product site and generate its synthetic reports with MoonBit."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEMOS = {
    "bbox": ("compare-ground-truth.json", "compare-baseline.json", "compare-candidate.json", "bbox", "ap50", 1.0, 0.25),
    "mask": ("mask-ground-truth.json", "mask-baseline.json", "mask-candidate.json", "segm", "ap", 0.0, 1.0),
    "polygon": ("polygon-ground-truth.json", "polygon-detections.json", "mask-candidate.json", "segm", "ap", 1.0, 1.0),
}
ASSETS = {
    "index.html": "site/index.html", "style.css": "site/style.css", "app.js": "site/app.js",
    "favicon.svg": "site/favicon.svg", "viewer/index.html": "viewer/index.html",
    "viewer/style.css": "viewer/style.css", "viewer/app.js": "viewer/app.js",
    "viewer/model.js": "viewer/model.js", "viewer/demos.js": "viewer/demos.js",
    "viewer/batch.js": "viewer/batch.js",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(output):
    output = output.resolve()
    if output == ROOT or (ROOT in output.parents and ROOT / "_build" not in output.parents):
        raise ValueError("Site output must be inside _build or outside the source checkout")
    output.mkdir(parents=True, exist_ok=True)
    for target, source in ASSETS.items():
        path = output / target
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / source, path)
    (output / ".nojekyll").write_text("", encoding="utf-8")
    manifest = {"schema_version": "1", "synthetic": True,
                "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "source_modified": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT)),
                "demos": {}}
    for name, (gt, baseline, candidate, geometry, metric, expected_left, expected_right) in DEMOS.items():
        inputs = ["examples/" + value for value in (gt, baseline, candidate)]
        command = ["moon", "run", "cli", "--target", "native", "--", inputs[0], inputs[1],
                   "--iou-type", geometry, "--compare", inputs[2], "--diagnostics", "--image-ranking", "--pr-curves"]
        expected_exit = 3 if name == "bbox" else 0
        if name == "bbox":
            inputs.append("examples/regression-policy.json")
            command += ["--gate-policy", inputs[-1]]
        result = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", capture_output=True)
        assert result.returncode == expected_exit, (name, result.returncode, result.stderr)
        report = json.loads(result.stdout)
        assert report["schema_version"] == "0.1.0"
        assert report["baseline"]["evaluator_version"] == report["candidate"]["evaluator_version"] == "0.2.0"
        left, right = report["baseline"]["summary"][metric], report["candidate"]["summary"][metric]
        assert abs(left - expected_left) < 1e-9 and abs(right - expected_right) < 1e-9, (name, left, right)
        if name == "polygon":
            assert all(row["delta"] in (None, 0) for row in report["metrics"])
        if name == "bbox":
            gates = report["metric_gates"]
            assert gates["status"] == "failed" and gates["checks"][0]["reason"] == "drop_exceeded"
            assert gates["checks"][0]["drop"] == 0.75
        report_path = output / "demos" / (name + ".json")
        report_path.parent.mkdir(exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        manifest["demos"][name] = {"report": name + ".json", "report_sha256": sha(report_path),
                                   "iou_type": geometry, "metric": metric,
                                   "baseline": left, "candidate": right, "expected_exit_code": expected_exit,
                                   "inputs": {path: sha(ROOT / path) for path in inputs}, "command": command}
    (output / "demos" / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    expected = set(ASSETS) | {".nojekyll", "demos/manifest.json"} | {"demos/" + name + ".json" for name in DEMOS}
    actual = {path.relative_to(output).as_posix() for path in output.rglob("*") if path.is_file()}
    assert actual == expected, ("Unexpected site contents", actual ^ expected)
    assert not any(path.is_symlink() for path in output.rglob("*"))
    print(json.dumps({"files": len(actual), "synthetic_demos": list(DEMOS), "evaluator_version": "0.2.0"}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "_build" / "site")
    build(parser.parse_args().output)
