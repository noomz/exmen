import hashlib
import http.server
import importlib.util
import os
import socketserver
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

MODULE = Path(__file__).resolve().parents[2] / 'scripts' / 'publish_release.py'
spec = importlib.util.spec_from_file_location('publish_release', MODULE)
publisher = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = publisher
spec.loader.exec_module(publisher)

SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass


def start_http(root):
    handler = lambda *args, **kwargs: QuietHandler(*args, directory=str(root), **kwargs)
    server = socketserver.ThreadingTCPServer(('127.0.0.1', 0), handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    return server, f'http://127.0.0.1:{port}'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.store = self.root / 'store'
        self.store.mkdir()
        self.dmg = self.root / 'Exmen-1.2.3.dmg'
        self.dmg.write_bytes(b'exmen-notarized-dmg-bytes')
        self.server, self.base = start_http(self.store)
        def stop_http():
            self.server.shutdown()
            self.server.server_close()
        self.addCleanup(stop_http)
        self.host = publisher.FileHost(self.store, self.base)
        self.intent = publisher.Intent(
            version='1.2.3', build=7, dmg=self.dmg,
            ed_signature='dGVzdFNpZw==', length=self.dmg.stat().st_size,
        )

    def appcast_items(self):
        xml = self.host.read_appcast()
        if xml is None:
            return []
        return publisher.parse_appcast(xml)

    def test_verifies_downloaded_digest_before_appcast_is_visible(self):
        seen = {'appcast': None}

        inner_fetch = self.host.fetch

        def fetch(url):
            seen['appcast'] = self.host.read_appcast()
            return inner_fetch(url)

        self.host.fetch = fetch
        result = publisher.publish(self.intent, self.host)
        self.assertEqual(result, 'published')
        self.assertIsNone(seen['appcast'])
        items = self.appcast_items()
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].build, 7)
        downloaded = publisher._http_get(items[0].url)
        self.assertEqual(hashlib.sha256(downloaded).hexdigest(), sha256(self.dmg))
        self.assertEqual(items[0].ed_signature, 'dGVzdFNpZw==')
        self.assertEqual(items[0].length, self.dmg.stat().st_size)
        enclosure = ET.fromstring(self.host.read_appcast()).find('channel/item/enclosure')
        self.assertEqual(enclosure.get(f'{{{SPARKLE_NS}}}edSignature'), 'dGVzdFNpZw==')

    def test_retry_is_idempotent(self):
        publisher.publish(self.intent, self.host)
        first = self.host.read_appcast()
        result = publisher.publish(self.intent, self.host)
        self.assertEqual(result, 'already-published')
        self.assertEqual(len(self.appcast_items()), 1)
        self.assertEqual(self.host.read_appcast(), first)
        assets = list((self.store / 'assets' / 'v1.2.3').glob('*.dmg'))
        self.assertEqual(len(assets), 1)

    def test_missing_artifact_does_not_publish_appcast(self):
        class Missing(publisher.FileHost):
            def put_asset(self, intent, data):
                return f'{self.base_url}/assets/{intent.tag}/{intent.asset_name}'

        host = Missing(self.store, self.base)
        with self.assertRaises(publisher.PublishError) as raised:
            publisher.publish(self.intent, host)
        self.assertIn('missing', str(raised.exception).lower())
        self.assertIsNone(host.read_appcast())

    def test_duplicate_build_is_rejected(self):
        publisher.publish(self.intent, self.host)
        other = self.root / 'Exmen-1.2.4.dmg'
        other.write_bytes(b'other-bytes-for-same-build')
        dup = publisher.Intent(version='1.2.4', build=7, dmg=other,
                               ed_signature='AAAA', length=other.stat().st_size)
        with self.assertRaises(publisher.PublishError) as raised:
            publisher.publish(dup, self.host)
        self.assertIn('already published', str(raised.exception))
        self.assertEqual(len(self.appcast_items()), 1)
        self.assertEqual(self.appcast_items()[0].version, '1.2.3')
        lower = publisher.Intent(version='1.2.4', build=6, dmg=other,
                                 ed_signature='BBBB', length=other.stat().st_size)
        with self.assertRaises(publisher.PublishError) as raised:
            publisher.publish(lower, self.host)
        self.assertIn('must exceed', str(raised.exception))

    def test_partial_failure_retries_without_duplicate_or_visible_feed(self):
        class Once(publisher.FileHost):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.writes = 0

            def write_appcast(self, xml):
                self.writes += 1
                if self.writes == 1:
                    raise publisher.PublishError('appcast write failed')
                super().write_appcast(xml)

        host = Once(self.store, self.base)
        with self.assertRaises(publisher.PublishError):
            publisher.publish(self.intent, host)
        self.assertIsNone(host.read_appcast())
        assets = list((self.store / 'assets' / 'v1.2.3').glob('*.dmg'))
        self.assertEqual(len(assets), 1)
        result = publisher.publish(self.intent, host)
        self.assertEqual(result, 'published')
        self.assertEqual(len(publisher.parse_appcast(host.read_appcast())), 1)
        result = publisher.publish(self.intent, host)
        self.assertEqual(result, 'already-published')
        self.assertEqual(len(publisher.parse_appcast(host.read_appcast())), 1)

    def test_digest_mismatch_hides_appcast(self):
        class Wrong(publisher.FileHost):
            def fetch(self, url):
                return b'not-the-dmg'

        host = Wrong(self.store, self.base)
        with self.assertRaises(publisher.PublishError) as raised:
            publisher.publish(self.intent, host)
        self.assertIn('digest', str(raised.exception).lower())
        self.assertIsNone(host.read_appcast())

    def test_github_backend_refuses_without_approval_and_test_key(self):
        env = os.environ.copy()
        env['PUBLISH_SIG_LINE'] = f'sparkle:edSignature="dGVzdFNpZw==" length="{self.dmg.stat().st_size}"'
        env.pop('EXMEN_PUBLISH', None)
        cmd = ['python3', str(MODULE), '--dmg', str(self.dmg), '--version', '1.2.3',
               '--build', '7', '--backend', 'github', '--appcast-dir', str(self.store),
               '--account', 'exmen']
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('EXMEN_PUBLISH', result.stderr)
        env['EXMEN_PUBLISH'] = '1'
        cmd[-1] = 'exmen-test'
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('test Sparkle account', result.stderr)

    def test_shell_local_backend_round_trip(self):
        binary = self.root / 'bin'
        binary.mkdir()
        sign = binary / 'sign_update'
        sign.write_text(
            '#!/bin/bash\n'
            'file=""\n'
            'for arg in "$@"; do\n'
            '  case "$arg" in --account) shift;; -*) ;; *) file=$arg;; esac\n'
            'done\n'
            'for arg in "$@"; do [ -f "$arg" ] && file=$arg; done\n'
            'size=$(wc -c < "$file" | tr -d " ")\n'
            'printf \'sparkle:edSignature="dGVzdFNpZw==" length="%s"\\n\' "$size"\n'
        )
        sign.chmod(0o755)
        env = os.environ.copy()
        env.update(
            PATH=f'{binary}:{env["PATH"]}',
            RELEASE_VERSION='1.2.3',
            RELEASE_BUILD='7',
            DMG=str(self.dmg),
            BACKEND='local',
            STORE=str(self.store),
            BASE_URL=self.base,
            SPARKLE_ACCOUNT='exmen-test',
            SIGN_UPDATE=str(sign),
        )
        script = MODULE.parent / 'publish-release.sh'
        result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('published', result.stdout)
        self.assertEqual(len(self.appcast_items()), 1)
        result = subprocess.run(['bash', str(script)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('already-published', result.stdout)
        self.assertEqual(len(self.appcast_items()), 1)

    def test_github_host_uploads_then_serves_digest_before_feed(self):
        gh_root = self.root / 'gh'
        releases = gh_root / 'releases'
        releases.mkdir(parents=True)
        fake_gh = self.root / 'gh-bin'
        fake_gh.mkdir()
        gh = fake_gh / 'gh'
        gh.write_text(
            '#!/bin/bash\n'
            'set -euo pipefail\n'
            'printf "%s\\n" "$*" >> "$GH_LOG"\n'
            'store=$GH_STORE\n'
            'if [ "$1" = api ]; then\n'
            '  python3 - "$store" <<\'PY\'\n'
            'import json, sys\n'
            'from pathlib import Path\n'
            'root = Path(sys.argv[1])\n'
            'releases = []\n'
            'for tag_dir in sorted(root.glob("releases/*")):\n'
            '    if not tag_dir.is_dir():\n'
            '        continue\n'
            '    assets = [{"name": p.name} for p in tag_dir.glob("*.dmg")]\n'
            '    notes = (tag_dir / "notes").read_text() if (tag_dir / "notes").exists() else ""\n'
            '    releases.append({"tag_name": tag_dir.name, "body": notes, "assets": assets})\n'
            'print(json.dumps([releases]))\n'
            'PY\n'
            '  exit 0\n'
            'fi\n'
            'if [ "$1" = release ] && [ "$2" = view ]; then exit 1; fi\n'
            'if [ "$1" = release ] && [ "$2" = create ]; then\n'
            '  tag=$3\n'
            '  dest=$store/releases/$tag\n'
            '  mkdir -p "$dest"\n'
            '  echo CFBundleVersion=7 > "$dest/notes"\n'
            '  for arg in "$@"; do\n'
            '    if [ -f "$arg" ]; then cp "$arg" "$dest/$(basename "$arg")"; fi\n'
            '  done\n'
            '  mkdir -p "$store/download/$tag"\n'
            '  cp "$dest/"*.dmg "$store/download/$tag/" 2>/dev/null || true\n'
            '  exit 0\n'
            'fi\n'
            'exit 1\n'
        )
        gh.chmod(0o755)
        pages = self.store / 'pages'
        pages.mkdir()
        download = self.store / 'download'
        download.mkdir()
        env_log = self.root / 'gh.log'
        host = publisher.GitHubHost(
            'owner/exmen', pages,
            asset_base_url=f'{self.base}/download',
            gh=str(gh),
        )
        host._gh = lambda args, check=True: subprocess.run(
            [str(gh), *args], check=check, capture_output=True, text=True,
            env={**os.environ, 'GH_STORE': str(self.store), 'GH_LOG': str(env_log)},
        )
        result = publisher.publish(self.intent, host)
        self.assertEqual(result, 'published')
        items = publisher.parse_appcast(host.read_appcast())
        self.assertEqual(len(items), 1)
        self.assertEqual(publisher.sha256_bytes(publisher._http_get(items[0].url)), sha256(self.dmg))


if __name__ == '__main__':
    unittest.main()
