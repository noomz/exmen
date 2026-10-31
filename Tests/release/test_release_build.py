import importlib.util
import plistlib
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[2] / 'scripts' / 'check_release_build.py'
spec = importlib.util.spec_from_file_location('check_release_build', MODULE)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class ReleaseBuildTests(unittest.TestCase):
    def archive(self, path, entries):
        with zipfile.ZipFile(path, 'w') as archive:
            for name, build in entries:
                archive.writestr(name, plistlib.dumps({'CFBundleVersion': build}))

    def test_reads_application_build_not_nested_framework(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'release.zip'
            self.archive(path, [('Exmen.app/Contents/Info.plist', '5'),
                                ('Exmen.app/Contents/Frameworks/X.app/Contents/Info.plist', '999')])
            self.assertEqual(checker.build_from_zip(path), 5)

    def test_rejects_ambiguous_and_non_numeric_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'release.zip'
            for entries in ([('Exmen.app/Contents/Info.plist', '5.1')],
                            [('A.app/Contents/Info.plist', '1'), ('B.app/Contents/Info.plist', '2')], []):
                self.archive(path, entries)
                with self.assertRaises(ValueError):
                    checker.build_from_zip(path)

    def test_rejects_missing_published_history(self):
        with patch.object(checker.subprocess, 'check_output', return_value=b'[]'):
            with self.assertRaises(ValueError):
                checker.highest_published('owner/repo')

    def test_release_candidate_requires_notary_profile(self):
        env = os.environ.copy()
        env.update(RELEASE_VERSION='1.2.2', RELEASE_BUILD='6',
                   SPARKLE_FEED_URL='https://example.com/appcast.xml')
        env.pop('NOTARY_PROFILE', None)
        result = subprocess.run(['bash', str(MODULE.parent / 'release-candidate.sh')],
                                env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('NOTARY_PROFILE', result.stderr)

    def test_rejects_non_increasing_build(self):
        with patch.object(checker, 'highest_published', return_value=5):
            with patch('sys.argv', ['check_release_build.py', '5']):
                with self.assertRaises(ValueError):
                    checker.main()
            with patch('sys.argv', ['check_release_build.py', '6']):
                checker.main()


if __name__ == '__main__':
    unittest.main()
