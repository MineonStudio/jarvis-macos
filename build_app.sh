#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/Jarvis.app"
JARVIS_VERSION="${JARVIS_VERSION:-0.5.35}"
JARVIS_BUILD="${JARVIS_BUILD:-109}"

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

# Compile the macOS Asset Catalog as well as the legacy ICNS fallback. Recent
# system surfaces, including Privacy & Security, prefer Assets.car and the
# named AppIcon asset when resolving an application's icon.
rm -f "$APP_DIR/Contents/Resources/Assets.car" \
      "$APP_DIR/Contents/Resources/AppIcon.icns"
ACTOOL="$(xcrun --find actool 2>/dev/null || true)"
if [[ -n "$ACTOOL" && -f "$ROOT_DIR/Resources/AppIcon.appiconset/Contents.json" ]]; then
  ICON_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-app-icon.XXXXXX")"
  trap 'rm -rf "$ICON_STAGE"' EXIT
  mkdir -p "$ICON_STAGE/Assets.xcassets/AppIcon.appiconset" "$ICON_STAGE/output"
  cp "$ROOT_DIR/Resources/AppIcon.appiconset/Contents.json" \
     "$ICON_STAGE/Assets.xcassets/AppIcon.appiconset/Contents.json"
  cp "$ROOT_DIR/Resources/Jarvis.iconset/"*.png \
     "$ICON_STAGE/Assets.xcassets/AppIcon.appiconset/"
  "$ACTOOL" \
    --compile "$ICON_STAGE/output" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_STAGE/partial.plist" \
    "$ICON_STAGE/Assets.xcassets" >/dev/null
  cp "$ICON_STAGE/output/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
  cp "$ICON_STAGE/output/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_DIR/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP_DIR/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1 || true
fi

if [[ -n "${JARVIS_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --sign "$JARVIS_CODESIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  # Ad-hoc signing is enough for local development, but macOS may ask for
  # Screen Recording again after the executable changes. Use a stable Apple
  # Development identity for persistent TCC permissions when available.
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

# Refresh the local LaunchServices registration so System Settings and Finder
# resolve the standalone ICNS immediately after a local production build.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
echo "Built: $APP_DIR"
