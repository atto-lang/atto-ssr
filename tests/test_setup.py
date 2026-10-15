"""Host setup contracts; Maven is a fixture, not guest compiler proof."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class SetupContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy(Path(__file__).resolve().parents[1] / 'scripts/setup.sh', self.root / 'scripts/setup.sh')
        self.compiler = self.root / '.work/compiler'
        self.compiler.mkdir(parents=True)
        (self.compiler / 'pom.xml').write_text('<project/>')
        self.git('init', '-q')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
        (self.root / 'compiler.lock').write_text(self.git('rev-parse', 'HEAD'))
        (self.root / 'compiler-tree.txt').write_text(self.git('rev-parse', 'HEAD^{tree}'))
        self.launcher = self.root / '.work/ores'
        self.launcher.write_text('old executable')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        mvn = self.bin / 'mvn'
        mvn.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$SETUP_ARGS"\nexit "${SETUP_FAIL:-0}"\n')
        mvn.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.compiler), *args], text=True).strip()

    def run_setup(self, fail=False):
        return subprocess.run(['bash', 'scripts/setup.sh'], cwd=self.root, capture_output=True, text=True,
                              env={**os.environ, 'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
                                   'SETUP_ARGS': str(self.root / 'args'), 'SETUP_FAIL': '1' if fail else '0'})

    def test_success_cleans_classes_and_publishes_launcher(self):
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('clean\npackage\n', (self.root / 'args').read_text())
        self.assertIn('exec java', self.launcher.read_text())
        self.assertIn('OresMain --core-io=native-async-only', self.launcher.read_text())
        self.assertTrue(os.access(self.launcher, os.X_OK))

    def test_failed_build_removes_stale_launcher(self):
        self.assertNotEqual(self.run_setup(fail=True).returncode, 0)
        self.assertFalse(self.launcher.exists())

    def test_dirty_input_preserved_without_launcher(self):
        (self.compiler / 'pom.xml').write_text('local changes')
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertEqual((self.compiler / 'pom.xml').read_text(), 'local changes')
        self.assertFalse(self.launcher.exists())
        self.assertFalse((self.root / 'args').exists())

    def test_symlink_input_rejected_before_build(self):
        target = self.root / 'saved-compiler'
        self.compiler.rename(target)
        self.compiler.symlink_to(target, target_is_directory=True)
        self.assertNotEqual(self.run_setup().returncode, 0)
        self.assertFalse((self.root / 'args').exists())


if __name__ == '__main__':
    unittest.main()
