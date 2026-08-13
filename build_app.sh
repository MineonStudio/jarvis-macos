#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/Jarvis.app"
JARVIS_VERSION="${JARVIS_VERSION:-0.5.17}"
JARVIS_BUILD="${JARVIS_BUILD:-91}"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/Jarvis" "$APP_DIR/Contents/MacOS/Jarvis"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Keep the same bundle identity and install path while allowing normal
# version/build-number upgrades for future releases.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $JARVIS_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $JARVIS_BUILD" "$APP_DIR/Contents/Info.plist"

# Remove obsolete custom menu resources from upgraded bundles.
rm -f "$APP_DIR/Contents/Resources/JarvisMenuIcon.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarIcon.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarCapsuleDark.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarCapsuleLight.png"

if [[ -f "$ROOT_DIR/Resources/Jarvis.icns" ]]; then
  cp "$ROOT_DIR/Resources/Jarvis.icns" "$APP_DIR/Contents/Resources/Jarvis.icns"
fi

if [[ -n "${JARVIS_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --sign "$JARVIS_CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  # Ad-hoc signing is enough for local development, but macOS may ask for
  # Screen Recording again after the executable changes. Use a stable Apple
  # Development identity for persistent TCC permissions when available.
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi
echo "Built: $APP_DIR"
