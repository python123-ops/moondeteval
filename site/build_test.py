"""Check publication provenance against a real temporary Git repository."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("site_builder", Path(__file__).with_name("build.py"))
builder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(builder)


class SourceStateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="moondeteval-source-")
        self.root = Path(self.temporary.name)
        self.override = patch.object(builder, "ROOT", self.root)
        self.override.start()
        self.git("init", "--quiet")
        self.git("config", "core.autocrlf", "false")
        (self.root / ".gitignore").write_text("_build/\n", encoding="utf-8")
        (self.root / "source.txt").write_text("original\n", encoding="utf-8")
        self.git("add", ".")
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "fixture")

    def tearDown(self):
        self.override.stop()
        self.temporary.cleanup()

    def git(self, *arguments):
        return subprocess.check_output(["git", *arguments], cwd=self.root, stderr=subprocess.STDOUT, text=True).strip()

    def test_clean_checkout_records_the_actual_commit(self):
        self.assertEqual(builder.source_state(True),
                         {"source_commit": self.git("rev-parse", "HEAD"), "source_modified": False})

    def test_tracked_changes_are_rejected_before_writing_site_files(self):
        (self.root / "source.txt").write_text("changed\n", encoding="utf-8")
        self.assertTrue(builder.source_state()["source_modified"])
        output = self.root / "_build/site"
        with self.assertRaisesRegex(ValueError, "clean checkout:[\\s\\S]*M source.txt"):
            builder.build(output, require_clean=True)
        self.assertFalse(output.exists())

    def test_untracked_files_are_listed_and_rejected(self):
        directory = self.root / "new"
        directory.mkdir()
        (directory / "input.txt").write_text("uncommitted\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, r"\?\? new/input.txt"):
            builder.source_state(True)

    def test_ignored_build_outputs_preserve_a_clean_source_state(self):
        directory = self.root / "_build/site"
        directory.mkdir(parents=True)
        (directory / "generated.json").write_text("{}", encoding="utf-8")
        self.assertFalse(builder.source_state(True)["source_modified"])


if __name__ == "__main__":
    unittest.main()
