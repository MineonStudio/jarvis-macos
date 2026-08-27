#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
JARVIS_DEV_BUILD="${JARVIS_DEV_BUILD:-0}"
if [[ "$JARVIS_DEV_BUILD" == "1" ]]; then
  DEFAULT_APP_DIR="$ROOT_DIR/dist/Jarvis-Dev.app"
  DEFAULT_BUNDLE_IDENTIFIER="com.jarvis.mac.dev"
  DEFAULT_DISPLAY_NAME="贾维斯开发版"
  DEFAULT_BUNDLE_NAME="Jarvis-Dev"
else
  DEFAULT_APP_DIR="$ROOT_DIR/dist/Jarvis.app"
  DEFAULT_BUNDLE_IDENTIFIER="com.jarvis.mac"
  DEFAULT_DISPLAY_NAME="贾维斯"
  DEFAULT_BUNDLE_NAME="Jarvis"
fi
APP_DIR="${JARVIS_APP_DIR:-$DEFAULT_APP_DIR}"
JARVIS_BUNDLE_IDENTIFIER="${JARVIS_BUNDLE_IDENTIFIER:-$DEFAULT_BUNDLE_IDENTIFIER}"
JARVIS_DISPLAY_NAME="${JARVIS_DISPLAY_NAME:-$DEFAULT_DISPLAY_NAME}"
JARVIS_BUNDLE_NAME="${JARVIS_BUNDLE_NAME:-$DEFAULT_BUNDLE_NAME}"
JARVIS_VERSION="${JARVIS_VERSION:-1.0.2}"
JARVIS_BUILD="${JARVIS_BUILD:-226}"

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

# Keep production builds compatible with the installed app. Development
# builds opt into a separate identity so LaunchServices, TCC, preferences,
# Keychain entries, and application data remain isolated from production.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $JARVIS_BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $JARVIS_DISPLAY_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $JARVIS_BUNDLE_NAME" "$APP_DIR/Contents/Info.plist"
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

# Use the native Icon Composer asset as the Dock/Finder icon source. This
# preserves the layered macOS 26 composition instead of flattening it into a
# square PNG inside the system's rounded Dock tile. Keep CFBundleIconFile out
# of Info.plist: that legacy key makes Dock prefer the static jarvis.icns and
# bypass the light/dark Icon Composer specialization.
ICON_COMPOSER_DIR="$ROOT_DIR/Resources/jarvis.icon"
DOCK_ICON_DIR="$APP_DIR/Contents/Resources/DockIcons"
ASSET_PARTIAL_INFO="$APP_DIR/Contents/assetcatalog-info.plist"
rm -f "$APP_DIR/Contents/Resources/Assets.car" \
      "$APP_DIR/Contents/Resources/AppIcon.icns" \
      "$APP_DIR/Contents/Resources/Jarvis.icns" \
      "$APP_DIR/Contents/Resources/jarvis.icns" \
      "$ASSET_PARTIAL_INFO"

if [[ -d "$ICON_COMPOSER_DIR" ]]; then
  # Build deterministic light/dark ICNS files from the same Icon Composer
  # source. These retain the native rounded icon treatment while allowing
  # the running app to honor its own manual theme preference.
  mkdir -p "$DOCK_ICON_DIR"
  for staleDockIcon in "$DOCK_ICON_DIR"/*.icns(N); do
    rm -f "$staleDockIcon"
  done
  for staleDockIcon in "$DOCK_ICON_DIR"/*.png(N); do
    rm -f "$staleDockIcon"
  done

  ICON_VARIANT_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-icon-variants.XXXXXX")"
  trap 'rm -rf "$ICON_VARIANT_TEMP"' EXIT
  LIGHT_ICON_SOURCE="Codex 图像 2026年8月26日 15_31_01.png"
  DARK_ICON_SOURCE="Codex 图像 2026年8月26日 15_31_01-dark.png"

  for iconVariant in light dark; do
    VARIANT_ROOT="$ICON_VARIANT_TEMP/$iconVariant"
    VARIANT_ICON_DIR="$VARIANT_ROOT/jarvis.icon"
    VARIANT_OUTPUT_DIR="$VARIANT_ROOT/output"
    mkdir -p "$VARIANT_ICON_DIR/Assets" "$VARIANT_OUTPUT_DIR"
    cp "$ICON_COMPOSER_DIR/Assets"/*.png "$VARIANT_ICON_DIR/Assets/"
    cp "$ICON_COMPOSER_DIR/icon.json" "$VARIANT_ICON_DIR/icon.json"

    # Keep one default image specialization. The dark package points that
    # default to the dark source; the light package keeps the original.
    perl -0pi -e 's/,\s*\{\s*"appearance"\s*:\s*"dark"\s*,\s*"value"\s*:\s*"[^"]+"\s*\}//s' \
      "$VARIANT_ICON_DIR/icon.json"
    if [[ "$iconVariant" == "dark" ]]; then
      perl -0pi -e "s/\Q$LIGHT_ICON_SOURCE\E/$DARK_ICON_SOURCE/g" \
        "$VARIANT_ICON_DIR/icon.json"
    fi

    xcrun actool \
      "$VARIANT_ICON_DIR" \
      --compile "$VARIANT_OUTPUT_DIR" \
      --platform macosx \
      --minimum-deployment-target 26.0 \
      --app-icon jarvis \
      --output-partial-info-plist "$VARIANT_ROOT/assetcatalog-info.plist" \
      --notices \
      --warnings >/dev/null
    cp "$VARIANT_OUTPUT_DIR/jarvis.icns" "$DOCK_ICON_DIR/jarvis-$iconVariant.icns"
  done

  xcrun actool \
    "$ICON_COMPOSER_DIR" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon jarvis \
    --output-partial-info-plist "$ASSET_PARTIAL_INFO" \
    --notices \
    --warnings >/dev/null
  rm -f "$ASSET_PARTIAL_INFO"
  # actool also emits a standalone jarvis.icns. Keep only Assets.car so the
  # bundle's CFBundleIconName resolves to the adaptive Icon Composer asset.
  rm -f "$APP_DIR/Contents/Resources/jarvis.icns"
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
