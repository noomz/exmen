#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail() { printf 'publish blocked: %s\n' "$*" >&2; exit 1; }

: "${RELEASE_VERSION:?Set RELEASE_VERSION}"
: "${RELEASE_BUILD:?Set RELEASE_BUILD}"
: "${DMG:?Set DMG to the notarized distribution image}"

BACKEND="${BACKEND:-github}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-exmen}"
SIGN_UPDATE="${SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"

[[ "$RELEASE_VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail 'invalid version'
[[ "$RELEASE_BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'invalid build'
test -f "$DMG" || fail 'DMG is missing'
test -x "$SIGN_UPDATE" || fail 'sign_update is missing'

if [ "$BACKEND" = github ]; then
  [ "${EXMEN_PUBLISH:-}" = 1 ] || fail 'set EXMEN_PUBLISH=1 after separate publication approval'
  : "${APPCAST_DIR:?Set APPCAST_DIR to a gh-pages checkout}"
  [ "$SPARKLE_ACCOUNT" = exmen-test ] && fail 'test Sparkle account cannot publish to GitHub'
fi

PUBLISH_SIG_LINE="$("$SIGN_UPDATE" --account "$SPARKLE_ACCOUNT" "$DMG")"
export PUBLISH_SIG_LINE

args=(python3 scripts/publish_release.py
  --dmg "$DMG"
  --version "$RELEASE_VERSION"
  --build "$RELEASE_BUILD"
  --backend "$BACKEND"
  --account "$SPARKLE_ACCOUNT")

if [ "$BACKEND" = local ]; then
  : "${STORE:?Set STORE to the local fixture directory}"
  : "${BASE_URL:?Set BASE_URL to the local HTTP origin}"
  args+=(--store "$STORE" --base-url "$BASE_URL")
else
  args+=(--appcast-dir "$APPCAST_DIR" --repository "${REPOSITORY:-noomz/exmen}")
  [ -n "${ASSET_BASE_URL:-}" ] && args+=(--asset-base-url "$ASSET_BASE_URL")
fi

python3 "${args[@]:1}"
unset PUBLISH_SIG_LINE
