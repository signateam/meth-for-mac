#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 [--configuration debug|release] [--arch ARCH]... [--sign IDENTITY]" >&2
  echo "  release builds default to --arch arm64 --arch x86_64; IDENTITY defaults to ad-hoc (-)" >&2
  exit 2
}

APP_NAME="Meth"
BUNDLE_ID="com.toli.trymeth"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
BIN_DIR="$CONTENTS/MacOS"
RESOURCE_DIR="$CONTENTS/Resources"
AGENT_DIR="$CONTENTS/Library/LaunchAgents"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"
DEALER_LABEL="$BUNDLE_ID.dealer"
SPARKLE_FEED_URL="https://trymeth.com/appcast.xml"
# Public half of the EdDSA update-signing key; the private half lives in the login keychain (generate_keys).
SPARKLE_PUBLIC_ED_KEY="hxXDISz2lMopqSaUqqyhx/0Y075xO7vTPNuwfT6IvNQ="

CONFIGURATION="debug"
ARCHS=()
IDENTITY="-"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration|-c) CONFIGURATION="${2:-}"; shift 2 ;;
    --arch) ARCHS+=("${2:-}"); shift 2 ;;
    --sign) IDENTITY="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || usage
[[ -n "$IDENTITY" ]] || usage
if [[ "$CONFIGURATION" == release && ${#ARCHS[@]} -eq 0 ]]; then
  ARCHS=(arm64 x86_64)
fi

# shellcheck source=version.env
source "$ROOT_DIR/script/version.env"

cd "$ROOT_DIR"
PRODUCTS=(Meth MethDealer)
STAGE_DIR="$DIST_DIR/bin"
/bin/rm -rf "$STAGE_DIR"
/bin/mkdir -p "$STAGE_DIR"
if [[ ${#ARCHS[@]} -eq 0 ]]; then
  /usr/bin/swift build -c "$CONFIGURATION"
  BUILD_DIR="$(/usr/bin/swift build -c "$CONFIGURATION" --show-bin-path)"
  for product in "${PRODUCTS[@]}"; do /bin/cp "$BUILD_DIR/$product" "$STAGE_DIR/$product"; done
else
  # 'swift build --arch A --arch B' needs Xcode's xcbuild; the Command Line Tools
  # can only build one triple at a time, so build each slice and merge with lipo.
  for arch in "${ARCHS[@]}"; do
    /usr/bin/swift build -c "$CONFIGURATION" --triple "$arch-apple-macosx15.0"
  done
  for product in "${PRODUCTS[@]}"; do
    slices=()
    for arch in "${ARCHS[@]}"; do
      slices+=("$(/usr/bin/swift build -c "$CONFIGURATION" --triple "$arch-apple-macosx15.0" --show-bin-path)/$product")
    done
    /usr/bin/lipo -create "${slices[@]}" -output "$STAGE_DIR/$product"
  done
fi

SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK" ]] || { echo "Sparkle.framework not found; run 'swift package resolve'" >&2; exit 1; }

/bin/rm -rf "$APP_BUNDLE"
/bin/mkdir -p "$BIN_DIR" "$RESOURCE_DIR" "$AGENT_DIR" "$FRAMEWORKS_DIR" "$DIST_DIR"
/bin/cp "$STAGE_DIR/Meth" "$BIN_DIR/Meth"
/bin/cp "$STAGE_DIR/MethDealer" "$BIN_DIR/MethDealer"
# ditto keeps the framework's Versions/Current symlinks intact.
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN_DIR/Meth"
/usr/bin/sips -s format png "$ROOT_DIR/Assets/github-mark.svg" --out "$RESOURCE_DIR/github-mark.png" >/dev/null
/usr/bin/sips -s format png "$ROOT_DIR/Assets/x-mark.svg" --out "$RESOURCE_DIR/x-mark.png" >/dev/null
/bin/cp "$ROOT_DIR/Assets/OCTICONS-LICENSE.txt" "$RESOURCE_DIR/OCTICONS-LICENSE.txt"
/bin/chmod 755 "$BIN_DIR/Meth" "$BIN_DIR/MethDealer"

/bin/cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Meth</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Meth</string>
  <key>CFBundleDisplayName</key><string>Meth</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Toli Marchuk</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null

# Meth Dealer, registered by the app with SMAppService.agent(plistName:).
/bin/cat > "$AGENT_DIR/$DEALER_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$DEALER_LABEL</string>
  <key>BundleProgram</key><string>Contents/MacOS/MethDealer</string>
  <key>AssociatedBundleIdentifiers</key><array><string>$BUNDLE_ID</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$AGENT_DIR/$DEALER_LABEL.plist" >/dev/null

/usr/bin/swift "$ROOT_DIR/script/make_icon.swift" "$DIST_DIR/icon-1024.png"
ICONSET="$DIST_DIR/AppIcon.iconset"
/bin/rm -rf "$ICONSET"
/bin/mkdir -p "$ICONSET"
for dimension in 16 32 128 256 512; do
  /usr/bin/sips -z "$dimension" "$dimension" "$DIST_DIR/icon-1024.png" --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
done
for dimension in 16 32 128 256 512; do
  doubled="$((dimension * 2))"
  /usr/bin/sips -z "$doubled" "$doubled" "$DIST_DIR/icon-1024.png" --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$RESOURCE_DIR/AppIcon.icns"

if [[ "$IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
else
  # Developer ID: hardened runtime and secure timestamp, innermost code first, never --deep.
  # Sparkle's nested code, as documented for apps that are not sandboxed.
  SPARKLE_VERSION_DIR="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
  sign() { /usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; }
  sign "$SPARKLE_VERSION_DIR/Autoupdate"
  sign "$SPARKLE_VERSION_DIR/Updater.app"
  sign --preserve-metadata=entitlements "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  sign "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
  sign "$FRAMEWORKS_DIR/Sparkle.framework"
  sign "$BIN_DIR/MethDealer"
  sign "$APP_BUNDLE"
  /usr/bin/codesign --verify --strict --deep "$APP_BUNDLE"
fi

echo "$APP_BUNDLE"
