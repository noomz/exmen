#!/usr/bin/env python3
"""Publish a signed Exmen DMG only after the versioned URL matches local bytes."""

from __future__ import annotations

import argparse
import email.utils
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol
from xml.etree import ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

TEMPLATE_PATH = Path(__file__).resolve().parent / "appcast.template.xml"
PRODUCTION_ACCOUNT = "exmen"
TEST_ACCOUNT = "exmen-test"
MIN_SYSTEM_VERSION = "13.0"


class PublishError(Exception):
    pass


@dataclass(frozen=True)
class Intent:
    version: str
    build: int
    dmg: Path
    ed_signature: str
    length: int

    @property
    def tag(self) -> str:
        return f"v{self.version}"

    @property
    def asset_name(self) -> str:
        return f"Exmen-{self.version}.dmg"


@dataclass(frozen=True)
class AssetRecord:
    tag: str
    name: str
    url: str
    build: int | None = None
    sha256: str | None = None


@dataclass(frozen=True)
class FeedItem:
    version: str
    build: int
    url: str
    ed_signature: str
    length: int


class Host(Protocol):
    def list_assets(self) -> list[AssetRecord]: ...
    def put_asset(self, intent: Intent, data: bytes) -> str: ...
    def fetch(self, url: str) -> bytes: ...
    def read_appcast(self) -> bytes | None: ...
    def write_appcast(self, xml: bytes) -> None: ...


def parse_sig_line(sig_line: str) -> tuple[str, int]:
    sig_match = re.search(r'sparkle:edSignature="([^"]+)"', sig_line)
    len_match = re.search(r'length="([^"]+)"', sig_line)
    if not sig_match or not len_match:
        raise PublishError("sign_update output missing edSignature or length")
    length = len_match.group(1)
    if not length.isdecimal():
        raise PublishError("sign_update length is not an integer")
    return sig_match.group(1), int(length)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sparkle(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def parse_appcast(xml: bytes | None) -> list[FeedItem]:
    if not xml:
        return []
    root = ET.fromstring(xml)
    channel = root.find("channel")
    if channel is None:
        raise PublishError("appcast has no channel")
    items = []
    for item in channel.findall("item"):
        version_el = item.find(_sparkle("version"))
        short_el = item.find(_sparkle("shortVersionString"))
        enclosure = item.find("enclosure")
        if version_el is None or enclosure is None:
            raise PublishError("appcast item missing version or enclosure")
        build = (version_el.text or "").strip()
        if not build.isdecimal():
            raise PublishError("appcast item build is not an integer")
        url = enclosure.get("url") or ""
        signature = enclosure.get(_sparkle("edSignature")) or enclosure.get("sparkle:edSignature") or ""
        length = enclosure.get("length") or ""
        if not url or not signature or not length.isdecimal():
            raise PublishError("appcast enclosure missing url, signature, or length")
        version = (short_el.text or "").strip() if short_el is not None else ""
        items.append(FeedItem(version=version, build=int(build), url=url,
                              ed_signature=signature, length=int(length)))
    return items


def seed_appcast() -> bytes:
    if not TEMPLATE_PATH.exists():
        raise PublishError(f"missing appcast template {TEMPLATE_PATH}")
    return TEMPLATE_PATH.read_bytes()


def render_appcast(existing: bytes | None, intent: Intent, url: str) -> bytes:
    xml = existing if existing else seed_appcast()
    tree = ET.ElementTree(ET.fromstring(xml))
    root = tree.getroot()
    channel = root.find("channel")
    if channel is None:
        raise PublishError("appcast has no channel")
    item = ET.Element("item")
    title = ET.SubElement(item, "title")
    title.text = f"Version {intent.version}"
    pub_date = ET.SubElement(item, "pubDate")
    pub_date.text = email.utils.formatdate(time.time(), usegmt=True)
    sparkle_version = ET.SubElement(item, ET.QName(SPARKLE_NS, "version"))
    sparkle_version.text = str(intent.build)
    sparkle_short = ET.SubElement(item, ET.QName(SPARKLE_NS, "shortVersionString"))
    sparkle_short.text = intent.version
    sparkle_min = ET.SubElement(item, ET.QName(SPARKLE_NS, "minimumSystemVersion"))
    sparkle_min.text = MIN_SYSTEM_VERSION
    enclosure = ET.SubElement(item, "enclosure")
    enclosure.set("url", url)
    enclosure.set(_sparkle("edSignature"), intent.ed_signature)
    enclosure.set("length", str(intent.length))
    enclosure.set("type", "application/octet-stream")
    insert_at = 0
    metadata = {"title", "link", "description", "language"}
    for i, child in enumerate(list(channel)):
        if child.tag in metadata:
            insert_at = i + 1
        elif child.tag == "item":
            insert_at = i
            break
    channel.insert(insert_at, item)
    if sys.version_info >= (3, 9):
        ET.indent(tree, space="    ")
    buf = io.BytesIO()
    tree.write(buf, encoding="utf-8", xml_declaration=True)
    return buf.getvalue()


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def publish(intent: Intent, host: Host) -> str:
    data = intent.dmg.read_bytes()
    digest = sha256_bytes(data)
    if intent.length != len(data):
        raise PublishError("sign_update length does not match DMG size")

    appcast = host.read_appcast()
    items = parse_appcast(appcast)
    assets = host.list_assets()

    same_item = [item for item in items if item.build == intent.build]
    if same_item:
        item = same_item[0]
        if not _item_matches(item, intent):
            raise PublishError(f"build {intent.build} already published with different enclosure")
        remote = host.fetch(item.url)
        if sha256_bytes(remote) != digest:
            raise PublishError("published artifact digest does not match local DMG")
        return "already-published"

    known_builds = {item.build for item in items}
    for asset in assets:
        if asset.build is None:
            continue
        if asset.tag == intent.tag and asset.name == intent.asset_name:
            continue
        known_builds.add(asset.build)
    if known_builds and intent.build <= max(known_builds):
        raise PublishError(
            f"build {intent.build} must exceed published maximum {max(known_builds)}"
        )

    url = None
    for asset in assets:
        if asset.tag == intent.tag and asset.name == intent.asset_name:
            url = asset.url
            break
    if url is None:
        url = host.put_asset(intent, data)

    try:
        remote = host.fetch(url)
    except PublishError:
        raise
    except (OSError, urllib.error.URLError) as error:
        raise PublishError(f"artifact missing at versioned URL: {error}") from error
    if not remote:
        raise PublishError("artifact missing at versioned URL")
    if sha256_bytes(remote) != digest:
        raise PublishError("downloaded digest does not match local DMG")

    xml = render_appcast(appcast, intent, url)
    host.write_appcast(xml)
    return "published"


def _item_matches(item: FeedItem, intent: Intent) -> bool:
    return (
        item.build == intent.build
        and item.version == intent.version
        and item.ed_signature == intent.ed_signature
        and item.length == intent.length
    )


class FileHost:
    """Directory + HTTP origin used by tests and local staging."""

    def __init__(self, root: Path, base_url: str, fetcher=None):
        self.root = root
        self.base_url = base_url.rstrip("/")
        self._fetcher = fetcher or _http_get
        self.index_path = root / "index.json"
        self.appcast_path = root / "appcast.xml"
        (root / "assets").mkdir(parents=True, exist_ok=True)

    def _index(self) -> list[dict]:
        if not self.index_path.exists():
            return []
        return json.loads(self.index_path.read_text())["assets"]

    def _save_index(self, assets: list[dict]) -> None:
        _atomic_write(self.index_path, json.dumps({"assets": assets}, indent=2).encode())

    def list_assets(self) -> list[AssetRecord]:
        return [AssetRecord(**row) for row in self._index()]

    def put_asset(self, intent: Intent, data: bytes) -> str:
        dest = self.root / "assets" / intent.tag / intent.asset_name
        dest.parent.mkdir(parents=True, exist_ok=True)
        _atomic_write(dest, data)
        url = f"{self.base_url}/assets/{intent.tag}/{intent.asset_name}"
        assets = self._index()
        assets.append({
            "tag": intent.tag,
            "name": intent.asset_name,
            "url": url,
            "build": intent.build,
            "sha256": sha256_bytes(data),
        })
        self._save_index(assets)
        return url

    def fetch(self, url: str) -> bytes:
        return self._fetcher(url)

    def read_appcast(self) -> bytes | None:
        if not self.appcast_path.exists():
            return None
        return self.appcast_path.read_bytes()

    def write_appcast(self, xml: bytes) -> None:
        _atomic_write(self.appcast_path, xml)


class GitHubHost:
    """GitHub Releases for the DMG, a gh-pages checkout for the appcast."""

    def __init__(self, repository: str, appcast_dir: Path, asset_base_url: str | None = None,
                 gh: str = "gh", fetcher=None):
        self.repository = repository
        self.appcast_dir = appcast_dir
        self.asset_base_url = (asset_base_url or f"https://github.com/{repository}/releases/download").rstrip("/")
        self.gh = gh
        self._fetcher = fetcher or _http_get
        self.appcast_path = appcast_dir / "appcast.xml"

    def _gh(self, args: list[str], check: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run([self.gh, *args], check=check, capture_output=True, text=True)

    def list_assets(self) -> list[AssetRecord]:
        result = self._gh(["api", "--paginate", "--slurp", f"repos/{self.repository}/releases"])
        pages = json.loads(result.stdout or "[]")
        records = []
        for release in (item for page in pages for item in page):
            build = _build_from_notes(release.get("body") or "")
            tag = release.get("tag_name") or ""
            for asset in release.get("assets") or []:
                name = asset.get("name") or ""
                if not name.lower().endswith(".dmg"):
                    continue
                url = f"{self.asset_base_url}/{tag}/{name}"
                records.append(AssetRecord(tag=tag, name=name, url=url, build=build))
        return records

    def put_asset(self, intent: Intent, data: bytes) -> str:
        if data != intent.dmg.read_bytes():
            raise PublishError("upload bytes do not match DMG")
        notes = f"CFBundleVersion={intent.build}"
        view = self._gh(["release", "view", intent.tag, "-R", self.repository], check=False)
        if view.returncode != 0:
            self._gh(["release", "create", intent.tag, "-R", self.repository,
                      "--title", intent.version, "--notes", notes,
                      str(intent.dmg)])
        else:
            self._gh(["release", "upload", intent.tag, str(intent.dmg),
                      "-R", self.repository, "--clobber"])
        return f"{self.asset_base_url}/{intent.tag}/{intent.asset_name}"

    def fetch(self, url: str) -> bytes:
        return self._fetcher(url)

    def read_appcast(self) -> bytes | None:
        if not self.appcast_path.exists():
            return None
        return self.appcast_path.read_bytes()

    def write_appcast(self, xml: bytes) -> None:
        _atomic_write(self.appcast_path, xml)


def _build_from_notes(body: str) -> int | None:
    match = re.search(r"CFBundleVersion=([0-9]+)", body)
    if not match:
        return None
    return int(match.group(1))


def _http_get(url: str) -> bytes:
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            if getattr(response, "status", 200) >= 400:
                raise PublishError(f"artifact missing at versioned URL: HTTP {response.status}")
            return response.read()
    except urllib.error.HTTPError as error:
        raise PublishError(f"artifact missing at versioned URL: HTTP {error.code}") from error


def _validate_account(account: str, backend: str) -> None:
    if backend == "github" and account == TEST_ACCOUNT:
        raise PublishError("test Sparkle account cannot publish to GitHub")
    if account not in {PRODUCTION_ACCOUNT, TEST_ACCOUNT}:
        raise PublishError(f"unknown Sparkle account {account}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dmg", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True, type=int)
    parser.add_argument("--backend", choices=("local", "github"), required=True)
    parser.add_argument("--store", type=Path)
    parser.add_argument("--base-url")
    parser.add_argument("--repository", default="noomz/exmen")
    parser.add_argument("--appcast-dir", type=Path)
    parser.add_argument("--asset-base-url")
    parser.add_argument("--account", default=os.environ.get("SPARKLE_ACCOUNT", PRODUCTION_ACCOUNT))
    args = parser.parse_args(argv)

    sig_line = os.environ.get("PUBLISH_SIG_LINE")
    if not sig_line:
        raise PublishError("set PUBLISH_SIG_LINE from sign_update; do not pass the private key")
    signature, length = parse_sig_line(sig_line)
    if not args.dmg.is_file():
        raise PublishError("DMG is missing")
    if args.build <= 0:
        raise PublishError("build must be positive")
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){1,2}", args.version):
        raise PublishError("invalid version")
    _validate_account(args.account, args.backend)

    intent = Intent(version=args.version, build=args.build, dmg=args.dmg,
                    ed_signature=signature, length=length)
    if args.backend == "github":
        if os.environ.get("EXMEN_PUBLISH") != "1":
            raise PublishError("refusing GitHub publish without EXMEN_PUBLISH=1")
        if not args.appcast_dir:
            raise PublishError("--appcast-dir is required for github backend")
        host: Host = GitHubHost(args.repository, args.appcast_dir, args.asset_base_url)
    else:
        if not args.store or not args.base_url:
            raise PublishError("--store and --base-url are required for local backend")
        host = FileHost(args.store, args.base_url)

    result = publish(intent, host)
    print(f"{result} {intent.tag} build {intent.build}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PublishError as error:
        print(f"publish blocked: {error}", file=sys.stderr)
        sys.exit(1)
