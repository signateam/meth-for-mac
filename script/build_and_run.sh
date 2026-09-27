#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Meth"
BUNDLE_ID="com.toli.meth"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
BIN_DIR="$CONTENTS/MacOS"
RESOURCE_DIR="$CONTENTS/Resources"

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
cd "$ROOT_DIR"
/usr/bin/swift build
BUILD_DIR="$(/usr/bin/swift build --show-bin-path)"

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$BIN_DIR" "$RESOURCE_DIR" "$DIST_DIR"
/bin/cp "$BUILD_DIR/Meth" "$BIN_DIR/Meth"
/bin/cp "$BUILD_DIR/MethDealer" "$BIN_DIR/MethDealer"
/bin/cp "$ROOT_DIR/script/install-power-access.sh" "$RESOURCE_DIR/install-power-access.sh"
/bin/chmod 755 "$BIN_DIR/Meth" "$BIN_DIR/MethDealer" "$RESOURCE_DIR/install-power-access.sh"

/bin/cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Meth</string>
  <key>CFBundleIdentifier</key><string>com.toli.meth</string>
  <key>CFBundleName</key><string>Meth</string>
  <key>CFBundleDisplayName</key><string>Meth</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST

/usr/bin/swift "$ROOT_DIR/script/make_icon.swift" "$DIST_DIR/icon-1024.png"
ICONSET="$DIST_DIR/AppIcon.iconset"
/bin/mkdir -p "$ICONSET"
for dimension in 16 32 128 256 512; do
  /usr/bin/sips -z "$dimension" "$dimension" "$DIST_DIR/icon-1024.png" --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
done
for dimension in 16 32 128 256 512; do
  doubled="$((dimension * 2))"
  /usr/bin/sips -z "$doubled" "$doubled" "$DIST_DIR/icon-1024.png" --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCE_DIR/AppIcon.icns"
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

case "$MODE" in
  run)
    /usr/bin/open -n "$APP_BUNDLE"
    ;;
  --debug|debug)
    /usr/bin/lldb -- "$BIN_DIR/Meth"
    ;;
  --logs|logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "Meth"'
    ;;
  --telemetry|telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    /usr/bin/open -n "$APP_BUNDLE"
    /bin/sleep 1
    /usr/bin/pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
