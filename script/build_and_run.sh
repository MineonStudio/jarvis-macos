#!/bin/zsh
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Jarvis"
APP_BUNDLE="$ROOT_DIR/dist/Jarvis-Dev.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/Jarvis"

cd "$ROOT_DIR"

# The development app uses the same executable name as the production app.
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

JARVIS_DEV_BUILD=1 "$ROOT_DIR/build_app.sh"

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
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.jarvis.mac.dev"'
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    echo "Running: $APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
