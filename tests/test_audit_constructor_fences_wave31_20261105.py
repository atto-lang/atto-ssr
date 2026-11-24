"""Exercise SSR audit on isolated host fixtures; not guest or compiler evidence."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SSRConstructorGate(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for folder in ("src", "examples", "tests", "scripts"):
            (self.root / folder).mkdir()
        shutil.copy2(ROOT / "scripts/audit.sh", self.root / "scripts/audit.sh")
        (self.root / "src/normal.ores").write_text("define module Normal as\nend\n")

    def run_audit(self, expect):
        result = subprocess.run(
            ["bash", str(self.root / "scripts/audit.sh")],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode == 0, expect,
                         result.stdout + result.stderr)

    def test_canonical_module_does_not_fail_on_normal_source(self):
        (self.root / "examples/example.ores").write_text(
            "define module Example as\nend\n")
        self.run_audit(True)

    def test_untrusted_attribute_and_tag_constructors_rejected(self):
        for declaration in ("pub fnc bool_attr(", "pub fnc void_element(",
                            "pub fnc element(", "pub fnc style(",
                            "pub fnc script("):
            with self.subTest(declaration=declaration):
                path = self.root / "src/unsafe.ores"
                path.write_text(declaration + "String name) {}\n")
                self.run_audit(False)
                path.unlink()

    def test_nested_native_file_cannot_embed_java_island(self):
        nested = self.root / "examples/a/b"
        nested.mkdir(parents=True)
        (nested / "interop.ores").write_text("do java { unsafe(); }\n")
        self.run_audit(False)

    def test_markup_html_field_in_tests_is_not_public_api(self):
        (self.root / "tests/forged.ores").write_text(
            "pub fnc demo(): void { let x = markup.html; return; }\n")
        self.run_audit(False)


if __name__ == "__main__":
    unittest.main()
