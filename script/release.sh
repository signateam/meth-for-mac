#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [RELEASE_NOTES]" >&2
  echo "  builds, signs, notarizes and staples dist/Meth.dmg, copies it to site/download/" >&2
  echo "  and regenerates site/appcast.xml; RELEASE_NOTES is passed to make_appcast.sh" >&2
  echo "  env: METH_SIGN_IDENTITY (Developer ID), METH_NOTARY_PROFILE (notarytool keychain profile)" >&2
  exit 2
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Meth.app"
APP_ZIP="$DIST_DIR/Meth.zip"
DMG="$DIST_DIR/Meth.dmg"
SITE_DMG="$ROOT_DIR/site/download/Meth.dmg"
IDENTITY="${METH_SIGN_IDENTITY:-Developer ID Application: ANATOLIY VLADIMIROVICH MARCHUK (Z9884J6ZQT)}"
NOTARY_PROFILE="${METH_NOTARY_PROFILE:-meth-notary}"
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"

[[ $# -le 1 ]] || usage
NOTES="${1:-}"
[[ -z "$NOTES" || -f "$NOTES" ]] || { echo "not a file: $NOTES" >&2; exit 1; }

WORK_DIR="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$WORK_DIR"' EXIT

step() { printf '\n==> %s\n' "$*"; }

# Submits a file, waits, and prints the log (then fails) unless it was accepted.
notarize() {
  local file="$1" result id status
  result="$WORK_DIR/notary-$(/usr/bin/basename "$file").plist"
  /usr/bin/xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format plist >"$result" || true
  id="" status=""
  # plutil prints parse errors on stdout, so only read a result that is a plist.
  if /usr/bin/plutil -lint -s "$result" >/dev/null 2>&1; then
    id="$(/usr/bin/plutil -extract id raw -o - "$result" 2>/dev/null || true)"
    status="$(/usr/bin/plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  fi
  echo "notarytool: $(/usr/bin/basename "$file") submission ${id:-<none>} -> ${status:-<no status>}"
  if [[ "$status" != Accepted ]]; then
    /bin/cat "$result" >&2
    if [[ -n "$id" ]]; then
      /usr/bin/xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    exit 1
  fi
}

step "Check notarytool profile $NOTARY_PROFILE"
if ! /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
  echo "store it first (in an interactive terminal, not a '!' shell escape):" >&2
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple id> --team-id Z9884J6ZQT" >&2
  exit 1
fi

step "Build universal release bundle signed with $IDENTITY"
"$ROOT_DIR/script/bundle.sh" --configuration release --sign "$IDENTITY"
/usr/bin/codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"
if /usr/sbin/spctl -a -vv -t exec "$APP_BUNDLE"; then
  echo "spctl accepted the app before notarization (unexpected, continuing)"
else
  echo "spctl rejected the app before notarization (expected)"
fi

step "Notarize and staple the app"
/bin/rm -f "$APP_ZIP"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
notarize "$APP_ZIP"
/usr/bin/xcrun stapler staple "$APP_BUNDLE"
/usr/bin/xcrun stapler validate "$APP_BUNDLE"
/usr/sbin/spctl -a -vv -t exec "$APP_BUNDLE"
/bin/rm -f "$APP_ZIP"

step "Create, sign, notarize and staple the DMG"
DMG_ROOT="$WORK_DIR/dmg"
/bin/mkdir -p "$DMG_ROOT"
/usr/bin/ditto "$APP_BUNDLE" "$DMG_ROOT/Meth.app"
/bin/ln -s /Applications "$DMG_ROOT/Applications"
/bin/rm -f "$DMG"
/usr/bin/hdiutil create -volname Meth -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO -ov "$DMG"
/usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$DMG"
/usr/bin/codesign --verify --strict --verbose=2 "$DMG"
notarize "$DMG"
/usr/bin/xcrun stapler staple "$DMG"
/usr/sbin/spctl -a -vv -t open --context context:primary-signature "$DMG"
/usr/bin/xcrun stapler validate "$DMG"

step "Publish to site/"
/bin/mkdir -p "$(/usr/bin/dirname "$SITE_DMG")"
/bin/cp "$DMG" "$SITE_DMG"
# generate_appcast reading the key from the keychain triggers an access prompt;
# generate_keys created the item, so it can export it silently to a private temp file.
if [[ -z "${SPARKLE_KEY_FILE:-}" ]]; then
  (umask 077 && "$SPARKLE_BIN/generate_keys" -x "$WORK_DIR/sparkle-ed25519" >/dev/null)
  export SPARKLE_KEY_FILE="$WORK_DIR/sparkle-ed25519"
fi
"$ROOT_DIR/script/make_appcast.sh" "$SITE_DMG" ${NOTES:+"$NOTES"}

step "Done"
/bin/ls -lh "$SITE_DMG"
/usr/bin/shasum -a 256 "$SITE_DMG"
