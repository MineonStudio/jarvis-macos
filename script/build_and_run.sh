#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Jarvis-Dev"
BUNDLE_ID="com.jarvis.mac.dev"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Jarvis"

cd "$ROOT_DIR"
# Only stop a previously launched development bundle. The production app has
# the same executable name (Jarvis), so killing by process name would be unsafe.
pkill -f -- "$APP_BINARY" >/dev/null 2>&1 || true
JARVIS_DEV_BUILD=1 ./build_app.sh

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"Jarvis\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -f -- "$APP_BINARY" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
