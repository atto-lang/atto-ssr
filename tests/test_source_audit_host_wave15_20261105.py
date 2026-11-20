"""Exercise the real SSR source audit in isolated host fixtures; no guest execution."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SsrSourceAuditContracts(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        for part in ("src", "examples", "tests", "scripts"):
            (self.root / part).mkdir()
        shutil.copy2(ROOT / "scripts/audit.sh", self.root / "scripts/audit.sh")
        (self.root / "src/main.ores").write_text("define module Demo as\nend\n")
        (self.root / "tests/good.ores").write_text("define module Good as\nend\n")

    def audit(self, accepted):
        result = subprocess.run(
            ["bash", str(self.root / "scripts/audit.sh")],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_valid_canonical_module_is_admitted(self):
        self.audit(True)

    def test_java_file_in_tests_is_rejected(self):
        (self.root / "tests/Foreign.java").write_text("class Foreign {}\n")
        self.audit(False)

    def test_java_interop_inside_native_source_is_rejected(self):
        (self.root / "src/main.ores").write_text("java: unsafe\n")
        self.audit(False)

    def test_dynamic_struct_is_rejected(self):
        (self.root / "src/main.ores").write_text("let x = DynamicStruct{};\n")
        self.audit(False)

    def test_module_without_as_delimiter_is_rejected(self):
        (self.root / "src/main.ores").write_text("define module Bare\nend\n")
        self.audit(False)

    def test_untrusted_tag_constructor_is_rejected(self):
        (self.root / "src/main.ores").write_text("pub fnc element(String tag) {}\n")
        self.audit(False)

    def test_style_constructor_is_rejected(self):
        (self.root / "src/main.ores").write_text("pub fnc style(String css) {}\n")
        self.audit(False)

    def test_html_field_forgery_in_example_is_rejected(self):
        (self.root / "examples/unsafe.ores").write_text("let x = obj { html: 1 };\n")
        self.audit(False)

    def test_html_field_access_in_example_is_rejected(self):
        (self.root / "examples/unsafe.ores").write_text("return markup.html;\n")
        self.audit(False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
