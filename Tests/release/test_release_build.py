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

    def test_release_candidate_does_not_pipe_codesign_into_grep(self):
        text = (MODULE.parent / 'release-candidate.sh').read_text()
        self.assertNotIn('codesign -dv --verbose=2 "$app" 2>&1 | grep', text)
        self.assertIn('sig=$(codesign -dv --verbose=2 "$app" 2>&1)', text)

    def test_release_candidate_requires_notary_profile(self):
        env = os.environ.copy()
        env.update(RELEASE_VERSION='1.2.2', RELEASE_BUILD='6',
                   SPARKLE_FEED_URL='https://example.com/appcast.xml')
        env.pop('NOTARY_PROFILE', None)
        result = subprocess.run(['bash', str(MODULE.parent / 'release-candidate.sh')],
                                env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('NOTARY_PROFILE', result.stderr)

    def test_production_candidate_rejects_isolated_feed_host(self):
        env = os.environ.copy()
        env.update(RELEASE_VERSION='1.2.3', RELEASE_BUILD='6',
                   SPARKLE_FEED_URL='https://192.168.64.1:8443/appcast.xml',
                   NOTARY_PROFILE='exmen-notary')
        env.pop('EXMEN_ISOLATED_CHANNEL', None)
        result = subprocess.run(['bash', str(MODULE.parent / 'release-candidate.sh')],
                                env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('isolated feed requires EXMEN_ISOLATED_CHANNEL=1', result.stderr)

    def test_isolated_channel_skips_github_history(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        binary = root / 'bin'
        binary.mkdir()
        fake = '''#!/bin/bash
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$CALL_LOG"
if [ "$name" = xcrun ] && [ "$1" = notarytool ]; then printf '{}\n'; exit 0; fi
if [ "$name" = security ]; then printf '  1) Developer ID Application: Siriwat Uamngamsup (W6P9Y44LWU)\n'; exit 0; fi
if [ "$name" = curl ]; then exit 0; fi
if [ "$name" = xcodebuild ]; then exit 1; fi
exit 1
'''
        for name in ('security', 'xcrun', 'curl', 'xcodebuild'):
            path = binary / name
            path.write_text(fake)
            path.chmod(0o755)
        env = os.environ.copy()
        env.update(PATH=f'{binary}:{env["PATH"]}', CALL_LOG=str(root / 'calls'),
                   RELEASE_VERSION='1.2.3', RELEASE_BUILD='6',
                   SPARKLE_FEED_URL='https://192.168.64.1:8443/appcast.xml',
                   NOTARY_PROFILE='exmen-notary', EXMEN_ISOLATED_CHANNEL='1')
        result = subprocess.run(['bash', str(MODULE.parent / 'release-candidate.sh')],
                                env=env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('isolated channel: skipping GitHub build history', result.stderr)
        calls = (root / 'calls').read_text()
        self.assertIn('xcodebuild archive', calls)
        self.assertNotIn('check_release_build', calls)

    def run_notarization_fixture(self, failure=''):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        binary = root / 'bin'
        binary.mkdir()
        fake = '''#!/bin/bash
name=${0##*/}
printf '%s %s\\n' "$name" "$*" >> "$CALL_LOG"
if [ "$name" = xcrun ] && [ "$1" = stapler ] && [ "$2" = validate ] && [ "$3" = "$FAIL_VALIDATE" ]; then exit 1; fi
if [ "$name" = xcrun ] && [ "$1" = notarytool ]; then printf '{"status":"Accepted"}\\n'; fi
'''
        for name in ('ditto', 'xcrun', 'hdiutil', 'codesign', 'spctl'):
            path = binary / name
            path.write_text(fake)
            path.chmod(0o755)
        env = os.environ.copy()
        env.update(PATH=f'{binary}:{env["PATH"]}', CALL_LOG=str(root / 'calls'),
                   FAIL_VALIDATE=failure.replace('{work}', str(root)))
        result = subprocess.run(['bash', str(MODULE.parent / 'notarize-candidate.sh'),
                                 str(root / 'Exmen.app'), str(root / 'Exmen.dmg'),
                                 'profile', 'identity', str(root)], env=env, capture_output=True, text=True)
        return root, result, (root / 'calls').read_text().splitlines()

    def test_staples_app_before_packaging_and_validates_both_final_tickets(self):
        root, result, calls = self.run_notarization_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        app_submit = calls.index(f'xcrun notarytool submit {root}/Exmen-notary.zip --keychain-profile profile --wait --no-progress --output-format json')
        app_staple = calls.index(f'xcrun stapler staple {root}/Exmen.app')
        create = calls.index(f'hdiutil create -volname Exmen -srcfolder {root}/Exmen.app -format UDZO {root}/Exmen.dmg')
        dmg_submit = calls.index(f'xcrun notarytool submit {root}/Exmen.dmg --keychain-profile profile --wait --no-progress --output-format json')
        dmg_staple = calls.index(f'xcrun stapler staple {root}/Exmen.dmg')
        dmg_validate = calls.index(f'xcrun stapler validate {root}/Exmen.dmg')
        inner_validate = calls.index(f'xcrun stapler validate {root}/mount/Exmen.app')
        self.assertLess(app_submit, app_staple)
        self.assertLess(app_staple, create)
        self.assertLess(create, dmg_submit)
        self.assertLess(dmg_submit, dmg_staple)
        self.assertLess(dmg_staple, dmg_validate)
        self.assertLess(dmg_validate, inner_validate)

    def test_rejects_missing_ticket_on_final_dmg_or_inner_app(self):
        for path in ('{work}/Exmen.dmg', '{work}/mount/Exmen.app'):
            with self.subTest(path=path):
                root, result, calls = self.run_notarization_fixture(path)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'xcrun stapler validate {path.replace("{work}", str(root))}', calls)

    def test_rejects_non_increasing_build(self):
        with patch.object(checker, 'highest_published', return_value=5):
            with patch('sys.argv', ['check_release_build.py', '5']):
                with self.assertRaises(ValueError):
                    checker.main()
            with patch('sys.argv', ['check_release_build.py', '6']):
                checker.main()


if __name__ == '__main__':
    unittest.main()
