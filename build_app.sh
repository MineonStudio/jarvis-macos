#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/Jarvis.app"
JARVIS_VERSION="${JARVIS_VERSION:-0.5.81}"
JARVIS_BUILD="${JARVIS_BUILD:-155}"

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

# Compile the official macOS 26 Icon Composer document. The system renders
# its Default/Dark/Mono appearances and owns the Dock container and sizing.
ICON_BUNDLE="$ROOT_DIR/Resources/AppIcon.icon"
ICON_PARTIAL_INFO="$APP_DIR/Contents/assetcatalog-info.plist"
rm -f "$APP_DIR/Contents/Resources/Jarvis.icns" \
      "$APP_DIR/Contents/Resources/Assets.car" \
      "$APP_DIR/Contents/Resources/AppIcon.icns" \
      "$APP_DIR/Contents/Resources/AppIconDark.icns" \
      "$ICON_PARTIAL_INFO"

if [[ -d "$ICON_BUNDLE" ]]; then
  xcrun actool \
    "$ICON_BUNDLE" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --target-device mac \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --bundle-identifier com.jarvis.mac \
    --output-partial-info-plist "$ICON_PARTIAL_INFO" \
    --notices \
    --warnings >/dev/null
  rm -f "$ICON_PARTIAL_INFO"
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
# resolve the Asset Catalog icon immediately after a local production build.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
# Dock maintains a separate icon snapshot; make it reread the rebuilt bundle.
/usr/bin/killall Dock >/dev/null 2>&1 || true
echo "Built: $APP_DIR"
