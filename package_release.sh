#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${JARVIS_APP_DIR:-$ROOT_DIR/dist/Jarvis.app}"
OUTPUT_DIR="${JARVIS_OUTPUT_DIR:-$ROOT_DIR/dist/release}"

cd "$ROOT_DIR"
./build_app.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_DIR/Contents/Info.plist")
if [[ "$BUNDLE_ID" != "com.jarvis.mac" ]]; then
  echo "Refusing to make a stable release from bundle $BUNDLE_ID" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
DIRECT_ZIP="$OUTPUT_DIR/Jarvis-$VERSION-macos.zip"
UPDATE_ZIP="$OUTPUT_DIR/Jarvis-update.zip"
MANIFEST="$OUTPUT_DIR/Jarvis-update-manifest.json"
SIGNATURE="$OUTPUT_DIR/Jarvis-update-manifest.sig"
UPDATE_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-update.XXXXXX")"
trap 'find "$UPDATE_STAGING_DIR" -depth -delete' EXIT

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIRECT_ZIP"
ditto "$APP_DIR" "$UPDATE_STAGING_DIR/Jarvis.app"
/usr/libexec/PlistBuddy -c 'Set :JarvisInstallSource unknown' "$UPDATE_STAGING_DIR/Jarvis.app/Contents/Info.plist"
codesign --force --options runtime \
  --entitlements "$ROOT_DIR/Resources/Jarvis.entitlements" \
  --sign - "$UPDATE_STAGING_DIR/Jarvis.app" >/dev/null
codesign --verify --deep --strict "$UPDATE_STAGING_DIR/Jarvis.app"
ditto -c -k --sequesterRsrc --keepParent "$UPDATE_STAGING_DIR/Jarvis.app" "$UPDATE_ZIP"

JARVIS_APP_DIR="$APP_DIR" JARVIS_OUTPUT_DIR="$OUTPUT_DIR" ./package_dmg.sh

swift script/JarvisUpdateSigning.swift sign-manifest \
  "$VERSION" \
  "$BUILD" \
  "$BUNDLE_ID" \
  "$UPDATE_ZIP" \
  "$MANIFEST" \
  "$SIGNATURE"

echo "Release artifacts are ready in: $OUTPUT_DIR"
echo "Upload these files to the matching GitHub Release:"
echo "  $DIRECT_ZIP"
echo "  $OUTPUT_DIR/Jarvis-$VERSION-macos.dmg"
echo "  $UPDATE_ZIP"
echo "  $MANIFEST"
echo "  $SIGNATURE"
