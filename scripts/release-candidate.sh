#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { printf 'release candidate blocked: %s\n' "$*" >&2; exit 1; }
: "${RELEASE_VERSION:?Set RELEASE_VERSION}"
: "${RELEASE_BUILD:?Set RELEASE_BUILD}"
: "${SPARKLE_FEED_URL:?Set SPARKLE_FEED_URL to the production HTTPS appcast}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile}"

IDENTITY='Developer ID Application: Siriwat Uamngamsup (W6P9Y44LWU)'
TEAM='W6P9Y44LWU'
PUBLIC_KEY='u2Qi0V797BF+t7DyxOiHu90S7NLbhIx8S1SlFLvaHiA='
[[ "$RELEASE_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail 'invalid version'
[[ "$RELEASE_BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'invalid build'
python3 - "$SPARKLE_FEED_URL" "${EXMEN_ISOLATED_CHANNEL:-}" <<'PY'
import sys
from urllib.parse import urlsplit
u = urlsplit(sys.argv[1])
isolated = sys.argv[2] == '1'
if u.scheme != 'https' or not u.hostname or u.username or u.password or u.hostname.endswith('.invalid'):
    raise SystemExit('release candidate blocked: invalid production feed URL')
if isolated and u.hostname not in {'127.0.0.1', 'localhost', 'exmen-isolated.test'} and not u.hostname.startswith('192.168.64.'):
    raise SystemExit('release candidate blocked: isolated feed host not allowed')
if not isolated and (u.hostname in {'127.0.0.1', 'localhost'} or u.hostname.startswith('192.168.64.') or u.hostname.endswith('.test')):
    raise SystemExit('release candidate blocked: isolated feed requires EXMEN_ISOLATED_CHANNEL=1')
PY
identities=$(security find-identity -v -p codesigning)
[[ "$identities" == *"$IDENTITY"* ]] || fail 'Developer ID identity unavailable'
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json --no-progress >/dev/null || fail 'notary profile unavailable'
if [ "${EXMEN_PUBLISH:-}" = 1 ]; then
  fail 'release-candidate.sh does not publish'
fi
curl_ca=()
if [ -n "${ISOLATED_CA:-}" ]; then
  curl_ca=(--cacert "$ISOLATED_CA")
fi
curl --fail --silent --show-error --max-time 20 "${curl_ca[@]}" "$SPARKLE_FEED_URL" >/dev/null || fail 'feed unavailable'
if [ "${EXMEN_ISOLATED_CHANNEL:-}" = 1 ]; then
  printf 'isolated channel: skipping GitHub build history\n' >&2
else
  python3 scripts/check_release_build.py "$RELEASE_BUILD"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/exmen-release-candidate.XXXXXXXX")
archive="$work/Exmen.xcarchive"
export="$work/export"
output="$work/Exmen-$RELEASE_VERSION.dmg"
cat >"$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>developer-id</string><key>signingStyle</key><string>manual</string><key>signingCertificate</key><string>Developer ID Application</string><key>teamID</key><string>$TEAM</string><key>hardenedRuntime</key><true/></dict></plist>
PLIST
xcodebuild archive -project Exmen.xcodeproj -scheme Exmen -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" "DEVELOPMENT_TEAM=$TEAM" \
  "CURRENT_PROJECT_VERSION=$RELEASE_BUILD" "MARKETING_VERSION=$RELEASE_VERSION" \
  "SPARKLE_FEED_URL=$SPARKLE_FEED_URL"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export" -exportOptionsPlist "$work/ExportOptions.plist"
app="$export/Exmen.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$RELEASE_BUILD" || fail 'build metadata mismatch'
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$RELEASE_VERSION" || fail 'version metadata mismatch'
test "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist")" = "$SPARKLE_FEED_URL" || fail 'feed mismatch'
test "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")" = "$PUBLIC_KEY" || fail 'production public key mismatch'
codesign --verify --deep --strict --verbose=2 "$app"
sig=$(codesign -dv --verbose=2 "$app" 2>&1)
[[ "$sig" == *"TeamIdentifier=$TEAM"* ]] || fail 'wrong signing team'
[[ "$sig" == *runtime* ]] || fail 'hardened runtime missing'
for helper in "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" \
              "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" \
              "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" \
              "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"; do
  codesign --verify --strict --verbose=2 "$helper"
  helper_sig=$(codesign -dv --verbose=2 "$helper" 2>&1)
  [[ "$helper_sig" == *"TeamIdentifier=$TEAM"* ]] || fail "wrong signing team: $helper"
done
bash scripts/notarize-candidate.sh "$app" "$output" "$NOTARY_PROFILE" "$IDENTITY" "$work"
if [ -n "${CANDIDATE_DIR:-}" ]; then
  mkdir -p "$CANDIDATE_DIR"
  cp "$output" "$CANDIDATE_DIR/Exmen-$RELEASE_VERSION.dmg"
  output="$CANDIDATE_DIR/Exmen-$RELEASE_VERSION.dmg"
fi
printf 'Private candidate verified: %s\n' "$output"
printf 'Publication requires separate approval and verification of downloaded bytes.\n'
