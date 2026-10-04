# 从源码构建

正式包：

```bash
./build_app.sh
open dist/Jarvis.app
```

开发版用另一个 bundle id（`com.jarvis.mac.dev`），数据和权限与正式版分开：

```bash
./build_dev_app.sh
open dist/Jarvis-Dev.app
```

开发版默认用登录钥匙串里名为 `Jarvis Dev Signing` 的证书。没有这张证书时会退回 ad-hoc，每次编译后都要重新授权。可以这样建一张：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /tmp/jarvis.key -out /tmp/jarvis.crt \
  -subj "/CN=Jarvis Dev Signing/O=Jarvis Local" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
security import /tmp/jarvis.crt -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security import /tmp/jarvis.key -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
rm /tmp/jarvis.key /tmp/jarvis.crt
```

已有 Apple Development 证书时：

```bash
JARVIS_CODESIGN_IDENTITY="Apple Development: 你的名字" ./build_app.sh
```

发版用 `./package_release.sh`，步骤在 [update-release.md](update-release.md)。
