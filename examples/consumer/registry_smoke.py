"""Check the three published CV packages together without a source workspace."""

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERSIONS = {
    "python123-ops/moondeteval": "0.1.0",
    "python123-ops/mbmot": "0.3.0",
    "python123-ops/moon-cv-geometry": "0.2.2",
}
SOURCES = (
    "moon.mod", "moon.pkg", "mbmot_adapter.mbt", "geometry_adapter.mbt",
    "consumer_test.mbt", "geometry_adapter_test.mbt",
)
APP_PKG = '''import {
  "local/consumer",
  "python123-ops/moondeteval",
  "python123-ops/mbmot",
  "python123-ops/moon-cv-geometry/core" @geometry,
  "python123-ops/moon-cv-geometry/multiview",
}

supported_targets = "+native"
pkgtype(kind: "executable")
'''
APP_MAIN = '''///|
fn main raise {
  let source = @geometry.Rect2::new(
    min=@geometry.Point2::new(x=0.0, y=0.0),
    max=@geometry.Point2::new(x=10.0, y=10.0),
  )
  let transform = @multiview.Homography::new(matrix=@geometry.Mat3::{
    m00: 1.0, m01: 0.0, m02: 20.0,
    m10: 0.0, m11: 1.0, m12: 30.0,
    m20: 0.0, m21: 0.0, m22: 1.0,
  })
  let target = @consumer.warp_geometry_rect_to_box(source, transform) catch {
    error => abort(error.message())
  }
  let (x, y, width, height) = target.to_xywh()
  let detector_box = @mbmot.BoundingBox::from_xywh(x, y, width, height) catch {
    error => abort(error.message())
  }
  let detector_output = @mbmot.Detection::new(detector_box, 0.9, 5) catch {
    error => abort(error.message())
  }
  let predictions = @consumer.adapt_mbmot_frames(
    [(11, [detector_output]), (29, [detector_output])], [(5, 7)], 40,
  ) catch {
    error => abort(error.message())
  }
  let dataset = @moondeteval.Dataset::new(
    [@moondeteval.Image::new(11, 100, 100), @moondeteval.Image::new(29, 100, 100)],
    [@moondeteval.Category::new(7, "object")],
    [
      @moondeteval.GroundTruth::new(101, 11, 7, target, area=100.0),
      @moondeteval.GroundTruth::new(102, 29, 7, target, area=100.0),
    ],
  ) catch {
    error => abort(error.message())
  }
  let report = @moondeteval.evaluate(dataset, predictions) catch {
    error => abort(error.message())
  }
  if report.summary().ap50() != 1.0 || predictions[0].id() != 40 || predictions[1].id() != 41 {
    abort("published three-library integration failed")
  }
  println("AP50=1 images=2 detections=2")
}
'''


def command(root, *args):
    run = subprocess.run(["moon", *args], cwd=root, text=True,
                         capture_output=True, encoding="utf-8", errors="replace")
    if run.returncode:
        raise RuntimeError(f"moon {' '.join(args)} exited {run.returncode}:\n{run.stdout}\n{run.stderr}")
    return run.stdout.strip()


def check(root):
    for name in SOURCES:
        shutil.copy2(HERE / name, root / name)
    app = root / "app"
    app.mkdir()
    (app / "moon.pkg").write_text(APP_PKG, encoding="utf-8")
    (app / "main.mbt").write_text(APP_MAIN, encoding="utf-8")
    assert not (root / "moon.work").exists()
    tree = json.loads(command(root, "tree", "--json"))
    modules = {item["name"]: item for item in tree["modules"]}
    for name, expected in VERSIONS.items():
        item = modules[name]
        if (item["version"], item["source"]["kind"], item["workspace_member"]) != (expected, "registry", False):
            raise RuntimeError(f"not an exact independent registry dependency: {item}")
    command(root, "fmt")
    command(root, "fmt", "--check")
    command(root, "check", "--target", "all", "--deny-warn")
    tests = command(root, "test", "--target", "all", "--deny-warn")
    native = command(root, "run", "app", "--target", "native")
    if native != "AP50=1 images=2 detections=2":
        raise RuntimeError(f"unexpected native result: {native}")
    result = {"module_sources": {name: modules[name] for name in VERSIONS},
              "test_output": tests, "native_output": native,
              "commands": ["moon tree --json", "moon fmt --check",
                           "moon check --target all --deny-warn",
                           "moon test --target all --deny-warn", "moon run app --target native"]}
    (root / "registry-result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(native)
    print("Registry: " + ", ".join(f"{name}@{version}" for name, version in VERSIONS.items()))
    print("Four backends passed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, help="save independent module and result outside the repository")
    args = parser.parse_args()
    if args.output_dir:
        root = args.output_dir.resolve()
        if root.exists():
            parser.error(f"output directory already exists: {root}")
        root.mkdir(parents=True, exist_ok=False)
        check(root)
    else:
        with tempfile.TemporaryDirectory(prefix="moondeteval-registry-") as directory:
            check(Path(directory))


if __name__ == "__main__":
    main()
