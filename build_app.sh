#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/Jarvis.app"
JARVIS_VERSION="${JARVIS_VERSION:-0.8.14}"
JARVIS_BUILD="${JARVIS_BUILD:-198}"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/Jarvis" "$APP_DIR/Contents/MacOS/Jarvis"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -d "$ROOT_DIR/Resources/AIProviderIcons" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/AIProviderIcons"
  for staleIcon in \
    "$APP_DIR/Contents/Resources/AIProviderIcons"/*.png(N) \
    "$APP_DIR/Contents/Resources/AIProviderIcons"/*.svg(N); do
    rm -f "$staleIcon"
  done
  cp "$ROOT_DIR/Resources/AIProviderIcons"/*.png \
     "$ROOT_DIR/Resources/AIProviderIcons"/*.svg \
     "$APP_DIR/Contents/Resources/AIProviderIcons/"
fi

# Keep the same bundle identity and install path while allowing normal
# version/build-number upgrades for future releases.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $JARVIS_VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $JARVIS_BUILD" "$APP_DIR/Contents/Info.plist"

# Remove obsolete custom menu resources from upgraded bundles.
rm -f "$APP_DIR/Contents/Resources/JarvisMenuIcon.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarIcon.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarCapsuleDark.png" \
      "$APP_DIR/Contents/Resources/JarvisMenuBarCapsuleLight.png"

if [[ -f "$ROOT_DIR/Resources/JarvisMenuBarIcon.png" ]]; then
  cp "$ROOT_DIR/Resources/JarvisMenuBarIcon.png" \
     "$APP_DIR/Contents/Resources/JarvisMenuBarIcon.png"
fi

# Use the standard macOS Asset Catalog as the Dock/Finder icon source. This
# keeps CFBundleIconName/AppIcon and LaunchServices on one cacheable path.
ASSET_CATALOG_DIR="$ROOT_DIR/Resources/Assets.xcassets"
ASSET_PARTIAL_INFO="$APP_DIR/Contents/assetcatalog-info.plist"
rm -f "$APP_DIR/Contents/Resources/Assets.car" \
      "$APP_DIR/Contents/Resources/AppIcon.icns" \
      "$APP_DIR/Contents/Resources/Jarvis.icns" \
      "$ASSET_PARTIAL_INFO"

if [[ -d "$ASSET_CATALOG_DIR" ]]; then
  xcrun actool \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_PARTIAL_INFO" \
    --notices \
    --warnings \
    "$ASSET_CATALOG_DIR" >/dev/null
  rm -f "$ASSET_PARTIAL_INFO"
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
  "$LSREGISTER" -u "$APP_DIR" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
fi
echo "Built: $APP_DIR"
