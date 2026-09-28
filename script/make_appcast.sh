#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 ARCHIVE [RELEASE_NOTES]" >&2
  echo "  ARCHIVE is the notarized Meth .dmg (or .zip) that will be served from $DOWNLOAD_PREFIX" >&2
  echo "  RELEASE_NOTES is an optional .html, .md or .txt file embedded in the entry" >&2
  echo "  set SPARKLE_KEY_FILE to sign with a private key file instead of the login keychain" >&2
  exit 2
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_PREFIX="https://trymeth.com/download/"
SITE_APPCAST="$ROOT_DIR/site/appcast.xml"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"

[[ $# -ge 1 && $# -le 2 ]] || usage
ARCHIVE="$1"
NOTES="${2:-}"
[[ -f "$ARCHIVE" ]] || { echo "not a file: $ARCHIVE" >&2; exit 1; }
EXTENSION="${ARCHIVE##*.}"
[[ "$EXTENSION" == dmg || "$EXTENSION" == zip ]] || usage
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  (cd "$ROOT_DIR" && /usr/bin/swift package resolve)
fi

# The site serves one fixed file (Meth.dmg), so the feed carries only the newest
# version: stage the archive under that name in an empty folder with no deltas.
STAGE="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$STAGE"' EXIT
/bin/cp "$ARCHIVE" "$STAGE/Meth.$EXTENSION"
if [[ -n "$NOTES" ]]; then
  /bin/cp "$NOTES" "$STAGE/Meth.${NOTES##*.}"
fi

# Signs with the EdDSA private key that generate_keys stored in the login keychain
# (macOS asks once to let generate_appcast read it), or with SPARKLE_KEY_FILE.
"$SPARKLE_BIN/generate_appcast" \
  ${SPARKLE_KEY_FILE:+--ed-key-file "$SPARKLE_KEY_FILE"} \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://trymeth.com" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  ${NOTES:+--embed-release-notes} \
  "$STAGE"

# generate_appcast only warns when the key does not match the app's SUPublicEDKey.
if ! /usr/bin/grep -q 'sparkle:edSignature=' "$STAGE/appcast.xml"; then
  echo "appcast entry is unsigned; the signing key does not match SUPublicEDKey" >&2
  exit 1
fi
/bin/cp "$STAGE/appcast.xml" "$SITE_APPCAST"
echo "$SITE_APPCAST"
