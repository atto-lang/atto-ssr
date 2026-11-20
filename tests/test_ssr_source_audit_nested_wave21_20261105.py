"""Nested-path negative controls for real SSR audit.sh (host only)."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NestedSsrSourceAuditWave21(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for part in ("src/nested", "examples/deep", "tests/nested", "scripts"):
            (self.root / part).mkdir(parents=True)
        shutil.copyfile(ROOT / "scripts/audit.sh", self.root / "scripts/audit.sh")
        (self.root / "src/main.ores").write_text("define module Good as\nend\n")

    def check_audit(self, expected):
        result = subprocess.run(
            ["bash", str(self.root / "scripts/audit.sh")],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode == 0, expected, result.stderr)

    def test_canonical_nested_modules_pass(self):
        (self.root / "src/nested/okay.ores").write_text("define module Good as\nend\n")
        self.check_audit(True)

    def test_nested_java_file_rejected(self):
        (self.root / "tests/nested/Bad.java").write_text("class Bad {}\n")
        self.check_audit(False)

    def test_nested_java_interop_rejected(self):
        (self.root / "src/nested/unsafe.ores").write_text("do java { run(); }\n")
        self.check_audit(False)

    def test_nested_dynamic_struct_rejected(self):
        (self.root / "examples/deep/unsafe.ores").write_text("DynamicStruct\n")
        self.check_audit(False)

    def test_nested_missing_module_as_rejected(self):
        (self.root / "src/nested/unsafe.ores").write_text("define module Unsafe\nend\n")
        self.check_audit(False)

    def test_nested_boolean_attribute_constructor_rejected(self):
        (self.root / "src/nested/unsafe.ores").write_text("pub fnc bool_attr(String x) {}\n")
        self.check_audit(False)

    def test_nested_script_constructor_rejected(self):
        (self.root / "src/nested/unsafe.ores").write_text("pub fnc script(String x) {}\n")
        self.check_audit(False)

    def test_nested_markup_object_forgery_rejected(self):
        (self.root / "tests/nested/unsafe.ores").write_text("obj { html: fake }\n")
        self.check_audit(False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
