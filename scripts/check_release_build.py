#!/usr/bin/env python3
"""Reject a build number that does not exceed every published release."""

import argparse
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def build_from_zip(path):
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist()
                 if name.endswith('.app/Contents/Info.plist') and name.count('.app/') == 1]
        if len(names) != 1:
            raise ValueError(f'{path.name}: expected exactly one top-level app')
        return build_from_plist(plistlib.loads(archive.read(names[0])), path.name)


def build_from_plist(info, label):
    build = str(info.get('CFBundleVersion', ''))
    if not build.isascii() or not build.isdecimal():
        raise ValueError(f'{label}: build number is not a decimal integer')
    return int(build)


def build_from_dmg(path):
    result = subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(path)],
                            check=True, capture_output=True)
    info = plistlib.loads(result.stdout)
    mounts = [e['mount-point'] for e in info['system-entities'] if 'mount-point' in e]
    if len(mounts) != 1:
        for mount in mounts:
            subprocess.run(['hdiutil', 'detach', mount], check=True, stdout=subprocess.DEVNULL)
        raise ValueError(f'{path.name}: expected one mounted volume')
    try:
        apps = list(Path(mounts[0]).glob('*.app/Contents/Info.plist'))
        if len(apps) != 1:
            raise ValueError(f'{path.name}: expected exactly one app')
        return build_from_plist(plistlib.loads(apps[0].read_bytes()), path.name)
    finally:
        subprocess.run(['hdiutil', 'detach', mounts[0]], check=True, stdout=subprocess.DEVNULL)


def highest_published(repository):
    output = subprocess.check_output(['gh', 'api', '--paginate', '--slurp',
                                      f'repos/{repository}/releases'])
    pages = json.loads(output)
    builds = []
    with tempfile.TemporaryDirectory(prefix='exmen-release-history-') as tmp:
        for release in (item for page in pages for item in page if not item.get('draft')):
            assets = [a for a in release['assets'] if a['name'].lower().endswith(('.zip', '.dmg'))]
            if not assets:
                raise ValueError(f"{release['tag_name']}: no inspectable app artifact")
            for asset in assets:
                name = asset['name']
                if Path(name).name != name:
                    raise ValueError('invalid asset name')
                dest = Path(tmp) / str(asset['id'])
                dest.mkdir()
                subprocess.run(['gh', 'release', 'download', release['tag_name'], '-R', repository,
                                '--pattern', name, '--dir', str(dest)], check=True)
                artifact = dest / name
                build = build_from_zip(artifact) if name.lower().endswith('.zip') else build_from_dmg(artifact)
                print(f"{release['tag_name']} {name}: build {build}")
                builds.append(build)
    if not builds:
        raise ValueError('no published release builds found; establish baseline manually')
    return max(builds)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('build', type=int)
    parser.add_argument('--repository', default='noomz/exmen')
    args = parser.parse_args()
    if args.build <= 0:
        raise ValueError('build must be positive')
    highest = highest_published(args.repository)
    if args.build <= highest:
        raise ValueError(f'build {args.build} must exceed published maximum {highest}')
    print(f'build {args.build} exceeds published maximum {highest}')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile, KeyError) as error:
        print(f'release build check failed: {error}', file=sys.stderr)
        sys.exit(1)
