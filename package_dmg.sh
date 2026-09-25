#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${JARVIS_APP_DIR:-$ROOT_DIR/dist/Jarvis.app}"
OUTPUT_DIR="${JARVIS_OUTPUT_DIR:-$ROOT_DIR/dist}"

if [[ ! -d "$APP_DIR" ]]; then
  echo "App bundle not found: $APP_DIR (run ./build_app.sh first)" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")
DMG_PATH="$OUTPUT_DIR/Jarvis-$VERSION-macos.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-dmg.XXXXXX")"
trap 'find "$STAGING_DIR" -depth -delete' EXIT

mkdir -p "$OUTPUT_DIR"
ditto "$APP_DIR" "$STAGING_DIR/Jarvis.app"
ln -s /Applications "$STAGING_DIR/Applications"

codesign --verify --deep --strict "$STAGING_DIR/Jarvis.app"
hdiutil create \
  -volname "Jarvis $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
hdiutil verify "$DMG_PATH"

echo "Built: $DMG_PATH"
