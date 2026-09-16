#!/bin/zsh
#
# Installs Jarvis with a code-signing identity that lives on this Mac.
#
# Shipping builds are ad-hoc signed, so macOS treats every update as a
# different app and drops the Screen Recording, Accessibility, and Keychain
# grants with it. This script creates a self-signed certificate in your login
# keychain and signs the app with it, so grants made once survive updates.
#
# What it does, in order:
#   1. downloads the latest release zip over curl (which, unlike a browser,
#      does not set the quarantine flag, so Gatekeeper does not block it)
#   2. verifies the bundle identifier and that the signature is intact
#   3. creates a "Jarvis Local Signing" certificate if you do not have one
#   4. re-signs Jarvis.app with that certificate and the app's entitlements
#   5. replaces /Applications/Jarvis.app and launches it
#
# Nothing here leaves your Mac: the certificate and its private key stay in
# your login keychain. Pass --uninstall to remove the app and the certificate.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/MineonStudio/jarvis-macos/dev/install.sh | zsh
#   zsh install.sh --uninstall

set -euo pipefail

REPOSITORY="MineonStudio/jarvis-macos"
BUNDLE_IDENTIFIER="com.jarvis.mac"
APP_NAME="Jarvis.app"
# Overridable so the script can be exercised without touching /Applications or
# a real login keychain entry.
IDENTITY_NAME="${JARVIS_SIGNING_IDENTITY:-Jarvis Local Signing}"
INSTALL_DIR="${JARVIS_INSTALL_DIR:-/Applications}"
LAUNCH_AFTER_INSTALL=1

WORK_DIR=""
cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT

log() {
  print -r -- "$*"
}

die() {
  print -ru2 -- "错误：$*"
  exit 1
}

for argument in "$@"; do
  case "$argument" in
    --uninstall) UNINSTALL=1 ;;
    --no-launch) LAUNCH_AFTER_INSTALL=0 ;;
    -h|--help) log "用法：zsh install.sh [--no-launch] [--uninstall]"; exit 0 ;;
    *) die "未知参数：$argument" ;;
  esac
done

# Only worth interrupting a running copy when this is a replacement; a first
# install, or one aimed somewhere else, has nothing to quit.
quit_running_app_if_replacing() {
  [[ -d "${INSTALL_DIR}/${APP_NAME}" ]] || return 0
  log "退出正在运行的贾维斯…"
  osascript -e 'tell application "Jarvis" to quit' >/dev/null 2>&1 || true
  sleep 1
}

if [[ "${UNINSTALL:-0}" == "1" ]]; then
  quit_running_app_if_replacing
  rm -rf "${INSTALL_DIR}/${APP_NAME}"

  UNINSTALL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-uninstall.XXXXXX")"
  if security find-certificate -c "$IDENTITY_NAME" -p "$HOME/Library/Keychains/login.keychain-db" \
      > "$UNINSTALL_DIR/identity.crt" 2>/dev/null; then
    security remove-trusted-cert "$UNINSTALL_DIR/identity.crt" >/dev/null 2>&1 || true
    security delete-identity -c "$IDENTITY_NAME" >/dev/null 2>&1 || true
    log "已移除证书 ${IDENTITY_NAME} 及其信任设置。"
  fi
  rm -rf "$UNINSTALL_DIR"

  log "已移除 ${INSTALL_DIR}/${APP_NAME}"
  exit 0
fi

[[ "$(uname -s)" == "Darwin" ]] || die "只能在 macOS 上运行。"
if [[ -d "$INSTALL_DIR" ]]; then
  [[ -w "$INSTALL_DIR" ]] || die "${INSTALL_DIR} 不可写，请用管理员账户运行。"
else
  mkdir -p "$INSTALL_DIR" 2>/dev/null || die "无法创建 ${INSTALL_DIR}。"
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jarvis-install.XXXXXX")"

log "查询最新版本…"
RELEASE_JSON="$WORK_DIR/release.json"
curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "User-Agent: Jarvis installer" \
  "https://api.github.com/repos/${REPOSITORY}/releases/latest" > "$RELEASE_JSON" \
  || die "无法获取版本信息，请检查网络。"

VERSION="$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$RELEASE_JSON" | head -1)"
# Read the URL and digest from the asset object that carries the download, so
# a release with several files cannot pair a digest with the wrong archive.
# Same selection rule as the app: a .zip whose name mentions Jarvis.
ASSET_LINE="$(grep -n -i -m1 '"name": *"[^"]*jarvis[^"]*\.zip"' "$RELEASE_JSON" | cut -d: -f1)"
[[ -n "$ASSET_LINE" ]] || die "最新版本没有可用的安装包。"
# The remaining fields of that object follow its name; stop well before the
# next asset begins.
ASSET_JSON="$(tail -n +"$ASSET_LINE" "$RELEASE_JSON" | head -40)"
ZIP_URL="$(print -r -- "$ASSET_JSON" | sed -n 's/.*"browser_download_url": *"\([^"]*\)".*/\1/p' | head -1)"
DIGEST="$(print -r -- "$ASSET_JSON" | sed -n 's/.*"digest": *"\([^"]*\)".*/\1/p' | head -1)"
[[ -n "$VERSION" && -n "$ZIP_URL" ]] || die "最新版本没有可用的安装包。"

log "下载 ${VERSION}…"
ARCHIVE="$WORK_DIR/Jarvis.zip"
curl -fsSL -o "$ARCHIVE" "$ZIP_URL" || die "下载失败。"

if [[ -n "$DIGEST" ]]; then
  ACTUAL="sha256:$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
  [[ "$ACTUAL" == "$DIGEST" ]] || die "校验和不匹配，安装包可能不完整。"
  log "校验和匹配。"
fi

log "解压…"
/usr/bin/ditto -x -k "$ARCHIVE" "$WORK_DIR/extracted"
SOURCE_APP="$WORK_DIR/extracted/${APP_NAME}"
[[ -d "$SOURCE_APP" ]] || die "安装包里没有找到 ${APP_NAME}。"

EXTRACTED_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
  "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$EXTRACTED_BUNDLE_ID" == "$BUNDLE_IDENTIFIER" ]] \
  || die "安装包的 Bundle ID 是 ${EXTRACTED_BUNDLE_ID}，不是 ${BUNDLE_IDENTIFIER}。"
codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1 \
  || die "安装包的签名校验失败。"

if security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
  log "复用已有的本地证书 ${IDENTITY_NAME}。"
else
  log "为这台 Mac 生成签名证书 ${IDENTITY_NAME}…"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK_DIR/key.pem" -out "$WORK_DIR/cert.pem" \
    -subj "/CN=${IDENTITY_NAME}/O=Jarvis Local" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

  # -T authorizes codesign to use the key, which avoids a keychain prompt on
  # every future rebuild.
  security import "$WORK_DIR/cert.pem" -k "$HOME/Library/Keychains/login.keychain-db" \
    -T /usr/bin/codesign >/dev/null
  security import "$WORK_DIR/key.pem" -k "$HOME/Library/Keychains/login.keychain-db" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
  security find-identity -p codesigning | grep -qF "$IDENTITY_NAME" \
    || die "证书导入失败。"
fi

# Trusting the certificate is what makes grants survive. Keychain stores an
# item's allowed apps as code requirements and has to evaluate the chain to
# match one; with an untrusted certificate that evaluation fails, so macOS
# falls back to asking again on every replacement even though TCC (which does
# not check trust) keeps its grants. Trust is per-user and only affects code
# signed by this key, which never leaves this Mac.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
  log "把证书加入信任设置（仅本机生效）…"
  security find-certificate -c "$IDENTITY_NAME" -p "$HOME/Library/Keychains/login.keychain-db" \
    > "$WORK_DIR/identity.crt"
  security add-trusted-cert -r trustRoot -p codeSign \
    -k "$HOME/Library/Keychains/login.keychain-db" "$WORK_DIR/identity.crt" >/dev/null 2>&1 \
    || die "无法把证书加入信任设置。"
fi

cat > "$WORK_DIR/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
</dict>
</plist>
PLIST

log "使用本地证书签名…"
codesign --force --options runtime \
  --entitlements "$WORK_DIR/entitlements.plist" \
  --sign "$IDENTITY_NAME" "$SOURCE_APP" >/dev/null 2>&1 \
  || die "签名失败。"
codesign --verify --deep --strict "$SOURCE_APP" >/dev/null 2>&1 \
  || die "重签后的校验失败。"

quit_running_app_if_replacing

rm -rf "${INSTALL_DIR}/${APP_NAME}"
/usr/bin/ditto "$SOURCE_APP" "${INSTALL_DIR}/${APP_NAME}"
# The zip came from curl, but strip any quarantine flag that a previous
# browser download or an archive round-trip may have left behind.
xattr -dr com.apple.quarantine "${INSTALL_DIR}/${APP_NAME}" 2>/dev/null || true

log "已安装到 ${INSTALL_DIR}/${APP_NAME}"

if [[ "$LAUNCH_AFTER_INSTALL" == "1" ]]; then
  open "${INSTALL_DIR}/${APP_NAME}"
  log "已启动。首次运行请允许屏幕录制、辅助功能、麦克风和摄像头；"
  log "屏幕录制和辅助功能授权后需要重启一次贾维斯。"
fi
