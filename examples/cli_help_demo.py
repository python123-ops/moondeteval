"""Exercise the native CLI's help and argument diagnostics as real processes."""

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREFIX = ["moon", "run", "cli", "--target", "native", "--"]


def run(*args):
    return subprocess.run(
        PREFIX + list(args), cwd=ROOT, capture_output=True, text=True,
        encoding="utf-8",
    )


def main():
    for flag in ("--help", "-h"):
        result = run(flag)
        assert result.returncode == 0, (flag, result.stderr)
        assert result.stderr == "", result.stderr
        for phrase in ("ground-truth.json", "--prediction-format coco|yolo",
                       "--max-report-bytes N", "Exit codes:"):
            assert phrase in result.stdout, (flag, phrase)

    for args in ((), ("--pr-curves",),
                 ("--pr-curves", "examples/detections.json"),
                 ("examples/ground-truth.json", "--pr-curves")):
        result = run(*args)
        assert result.returncode == 2, (args, result.returncode, result.stderr)
        assert result.stdout == "", (args, result.stdout)
        assert "--help" in result.stderr, (args, result.stderr)
        assert "cannot inspect input" not in result.stderr, (args, result.stderr)

    result = run("examples/ground-truth.json", "examples/detections.json")
    assert result.returncode == 0, result.stderr
    report = json.loads(result.stdout)
    assert report["schema_version"] == "0.1.0"
    assert report["summary"]["ap50"] == 1
    print("CLI help, positional errors, and valid report: OK")


if __name__ == "__main__":
    main()
