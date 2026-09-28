#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Meth"
BUNDLE_ID="com.toli.trymeth"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
BIN_DIR="$APP_BUNDLE/Contents/MacOS"

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
"$ROOT_DIR/script/bundle.sh" --configuration debug

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
