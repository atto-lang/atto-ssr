"""Offline preflight of the real setup script; never clones or runs Maven."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SETUP = Path(__file__).resolve().parents[1] / "scripts/setup.sh"
GOOD_SHA = "a" * 40
GOOD_TREE = "b" * 40


class SetupLockPreflightWave31(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        (self.root / "scripts/setup.sh").write_bytes(SETUP.read_bytes())
        (self.root / "compiler.lock").write_text(GOOD_SHA + "\n")
        (self.root / "compiler-tree.txt").write_text(GOOD_TREE + "\n")

    def run_setup(self):
        return subprocess.run(["bash", str(self.root / "scripts/setup.sh")],
                              cwd=self.root, text=True, capture_output=True,
                              timeout=10, env={**os.environ, "GIT_TERMINAL_PROMPT": "0"})

    def test_non_hex_compiler_revision_is_denied_before_clone(self):
        (self.root / "compiler.lock").write_text("not-a-commit\n")
        run = self.run_setup()
        self.assertEqual(run.returncode, 65, run.stderr)
        self.assertIn("compiler revision and tree must be full Git SHAs", run.stderr)
        self.assertFalse((self.root / ".work/compiler").exists())

    def test_non_hex_tree_is_denied_before_clone(self):
        (self.root / "compiler-tree.txt").write_text("B" * 40 + "\n")
        run = self.run_setup()
        self.assertEqual(run.returncode, 65, run.stderr)
        self.assertIn("compiler revision and tree must be full Git SHAs", run.stderr)
        self.assertFalse((self.root / ".work/compiler").exists())

    def test_symlinked_work_directory_is_denied_without_touching_target(self):
        outside = self.root / "outside"
        outside.mkdir()
        marker = outside / "ores"
        marker.write_text("do not delete")
        (self.root / ".work").symlink_to(outside, target_is_directory=True)
        run = self.run_setup()
        self.assertEqual(run.returncode, 65, run.stderr)
        self.assertIn("compiler work directory must not be a symlink", run.stderr)
        self.assertEqual(marker.read_text(), "do not delete")

    def test_old_launcher_removed_when_pin_validation_fails(self):
        (self.root / ".work").mkdir()
        launcher = self.root / ".work/ores"
        launcher.write_text("stale launcher")
        (self.root / "compiler.lock").write_text("invalid")
        run = self.run_setup()
        self.assertEqual(run.returncode, 65, run.stderr)
        self.assertFalse(launcher.exists())


if __name__ == "__main__":
    unittest.main()
