#!/bin/bash
set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo 'usage: notarize-candidate.sh APP DMG PROFILE IDENTITY WORK_DIR' >&2
  exit 2
fi
app=$1
output=$2
profile=$3
identity=$4
work=$5

submit() {
  local artifact=$1 result=$2
  xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait --no-progress --output-format json > "$result"
  python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as result:
    if json.load(result).get('status') != 'Accepted':
        raise SystemExit('release candidate blocked: notarization not accepted')
PY
}

ditto -c -k --sequesterRsrc --keepParent "$app" "$work/Exmen-notary.zip"
submit "$work/Exmen-notary.zip" "$work/app-notarization.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
hdiutil create -volname Exmen -srcfolder "$app" -format UDZO "$output"
codesign --force --timestamp --sign "$identity" "$output"
submit "$output" "$work/dmg-notarization.json"
xcrun stapler staple "$output"
xcrun stapler validate "$output"
codesign --verify --strict --verbose=2 "$output"
spctl -a -vvv -t open --context context:primary-signature "$output"
mount="$work/mount"
mkdir "$mount"
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$output" >/dev/null
trap 'hdiutil detach "$mount" >/dev/null' EXIT
xcrun stapler validate "$mount/Exmen.app"
codesign --verify --deep --strict --verbose=2 "$mount/Exmen.app"
spctl -a -vvv "$mount/Exmen.app"
hdiutil detach "$mount" >/dev/null
trap - EXIT
