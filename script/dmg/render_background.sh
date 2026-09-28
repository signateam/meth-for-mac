#!/usr/bin/env bash
# Renders background.html at 1x and 2x with headless Chrome and combines them into
# background.tiff (a HiDPI TIFF that Finder picks the right size from).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TMP="$(/usr/bin/mktemp -d)"
trap '/bin/rm -rf "$TMP"' EXIT

for scale in 1 2; do
  suffix=""; [[ $scale == 2 ]] && suffix="@2x"
  # Chrome writes the screenshot but does not always exit, so wait for the file, then stop it.
  "$CHROME" --headless=new --hide-scrollbars --use-mock-keychain --no-first-run \
    --user-data-dir="$TMP/profile$scale" --force-device-scale-factor="$scale" --window-size=660,420 \
    --screenshot="$TMP/bg$suffix.png" "file://$DIR/background.html" >"$TMP/chrome$scale.log" 2>&1 &
  pid=$!
  for _ in $(seq 1 60); do
    [[ -s "$TMP/bg$suffix.png" ]] && /usr/bin/grep -q "bytes written" "$TMP/chrome$scale.log" && break
    /bin/sleep 0.5 2>/dev/null || /usr/bin/perl -e 'select(undef,undef,undef,0.5)'
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  /bin/pkill -f -- "--user-data-dir=$TMP/profile$scale" 2>/dev/null || true
  [[ -s "$TMP/bg$suffix.png" ]] || { echo "Chrome did not write bg$suffix.png" >&2; exit 1; }
done
/usr/bin/sips -g pixelWidth -g pixelHeight "$TMP/bg.png" "$TMP/bg@2x.png" | /usr/bin/grep pixel
/usr/bin/tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out "$DIR/background.tiff"
if [[ -n "${1:-}" ]]; then /bin/cp "$TMP/bg.png" "$TMP/bg@2x.png" "$1/"; fi
echo "$DIR/background.tiff"
