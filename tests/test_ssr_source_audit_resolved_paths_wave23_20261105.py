"""Host-only SSR audit boundary fixtures, not guest execution."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SsrAuditBoundaryWave23(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for directory in ('scripts', 'src/deep', 'examples', 'tests/reject'):
            (self.root / directory).mkdir(parents=True)
        shutil.copyfile(ROOT / 'scripts/audit.sh', self.root / 'scripts/audit.sh')
        (self.root / 'src/main.ores').write_text('define module App as\nend\n')
        (self.root / 'tests/positive.ores').write_text('define module Positive as\nend\n')

    def audit(self, expected, diagnostic=None):
        result = subprocess.run(['bash', str(self.root / 'scripts/audit.sh')],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode == 0, expected, result.stderr)
        if diagnostic:
            self.assertIn(diagnostic, result.stderr)

    def test_canonical_nested_module_and_public_call_are_accepted(self):
        (self.root / 'src/deep/view.ores').write_text('define module View as\nend\n')
        self.audit(True)

    def test_nested_element_constructor_is_refused(self):
        (self.root / 'src/deep/bad.ores').write_text('pub fnc element(String name) {}\n')
        self.audit(False, 'dynamic tag and attribute names')

    def test_nested_void_element_constructor_is_refused(self):
        (self.root / 'src/deep/bad.ores').write_text('pub fnc void_element(String name) {}\n')
        self.audit(False, 'dynamic tag and attribute names')

    def test_example_cannot_read_raw_markup_html_member(self):
        (self.root / 'examples/demo.ores').write_text('pub fnc main() { return node.html; }\n')
        self.audit(False, 'public API')

    def test_reject_fixture_cannot_forge_markup_html_member(self):
        (self.root / 'tests/reject/spoof.ores').write_text('obj { html: fake }\n')
        self.audit(False, 'forge the provisional Markup')


if __name__ == '__main__':
    unittest.main(verbosity=2)
