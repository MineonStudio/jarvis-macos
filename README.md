# 贾维斯

公开仓库：[MineonStudio/jarvis-macos](https://github.com/MineonStudio/jarvis-macos)

一个 API 驱动、可更换大脑、可扩展技能的 macOS AI 工具人。

## 当前 MVP

- SwiftUI 原生 macOS 应用外壳
- 设置中支持跟随系统、浅色和深色主题
- 框选截图
- ScreenCaptureKit 单帧抓取 + 自定义全屏暗幕、窗口命中和框选
- 截图后在原屏幕位置保留，截图窗口和工具栏独立分离且可一起拖动
- 箭头绘制、马赛克像素化、文本输入
- 标注撤销/重做
- 编辑后的截图另存为、复制和完成编辑
- 剪贴板历史记录，支持文本、图片、文件和视频
- 剪贴板独立面板（默认 F2）、类型筛选、收藏、搜索与快捷粘贴（⌘1–9 / 回车）
- 菜单栏常驻入口
- 会议记录：本机录音、说话人转写和 AI 总结
- 支持开机自启，可在设置中手动开启

## 安装

给使用者（不需要装编译环境）：

```bash
curl -fsSL https://raw.githubusercontent.com/MineonStudio/jarvis-macos/dev/install.sh | zsh
```

脚本会下载最新的 release、校验校验和、在本机生成一张自签名证书（"Jarvis Local Signing"，存在你的登录钥匙串里，不会离开这台 Mac），把它加入本机信任设置，再用它对 Jarvis.app 重新签名后安装到「应用程序」。

这样做的效果是：**屏幕录制和辅助功能授权只需要给一次，之后自动更新不再失效**——TCC 把授权记在证书锚定的代码身份上，更新时用同一张证书重签即可沿用。信任设置仅对本机生效，只影响这张密钥签出的代码，而密钥从不离开这台 Mac。

钥匙串是例外：实测更换二进制后系统仍会再问一次访问权限，即使证书已受信任，所以不要把 API Key 授权算进「只授一次」的收益里。

因为走 curl 而不是浏览器下载，安装包不会被加上 quarantine 标记，所以不会触发 Gatekeeper 拦截。`--uninstall` 可以连同证书一起卸载。

**已经手动装过的不用重装**：如果贾维斯是拖进「应用程序」的（发布包是 ad-hoc 签名，没有任何证书），首次启动的权限页会给出一张「为本机签名并重启」的卡片，做的正是上面同一件事——本机生成证书、签名、重启，之后权限同样只授一次。卡片只在检测到当前副本确实没有签名证书时出现，签过之后就不再显示。

## 构建

```bash
./build_app.sh
open dist/Jarvis.app
```

生成可拖入「应用程序」目录的 DMG：

```bash
./package_dmg.sh
open dist/Jarvis-1.4.5-macos.dmg
```

需要 macOS 26 或更高版本。升级时保持同一个 `com.jarvis.mac` Bundle ID 和 `dist/Jarvis.app` 路径，只递增版本号：

```bash
JARVIS_VERSION="1.4.5" JARVIS_BUILD="343" ./build_app.sh
```

应用图标资源名会随版本递增，避免 macOS 在覆盖安装后继续从 LaunchServices 或 Dock 图标缓存读取旧图标；用户通过新版 DMG 安装后无需手动清缓存或重启 Dock。

## 质量检查

本地提交前运行与 CI 相同的基础检查：

```bash
swiftformat --lint --config .swiftformat Sources Tests
swiftlint lint --config .swiftlint.yml
swift test
swift build -c release
git diff --check
```

项目使用 SwiftFormat 统一格式、SwiftLint 检查复杂度与规范，并在 GitHub Actions 中执行静态检查、测试和 Release 构建。持久化失败必须通过日志和用户可见状态反馈，不应静默忽略。

版本号会显示在设置页的“版本与更新”区域。发布新版本时使用 `v主版本.次版本.修订版本` 标签，并在 GitHub Releases 创建正式版本；设置页可检查 GitHub Releases 是否有新版本。发布包使用 ad-hoc 签名（没有付费 Apple Developer ID，因此无法公证）；每次替换二进制都会产生新的代码身份，屏幕录制和辅助功能授权无法沿用。点击“下载更新”后，Jarvis 会先在当前进程中用 tccutil 清除这两项旧授权，安装完成后再向用户重新申请。

用 `install.sh` 安装的副本不受这条限制：本机存在 `Jarvis Local Signing` 证书时，更新流程会在替换前用同一张证书重签新版，代码身份不变，因此跳过 tccutil 重置，屏幕录制和辅助功能授权沿用（钥匙串访问权限仍会重新询问一次，见上文「安装」一节）。

截图快捷键触发后，Jarvis 会先用 ScreenCaptureKit 冻结所有显示器画面，再显示自己的暗幕。悬停窗口会高亮，单击即可截取整个应用窗口；拖动则可以自定义框选区域，不会打开 macOS 的“共享整个屏幕”选择器。如果 macOS 要求授权，请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许贾维斯访问屏幕。

会议记录会同时保存麦克风和系统播放音频，原始录音和逐字稿留在本机；会议总结使用设置中的 AI 服务。首次使用前需要下载本地识别模型。默认快捷键为 F3，可在设置中修改。

截图快捷键默认为 F1，剪贴板历史默认使用 F2 唤起独立面板，两个快捷键都可以在对应技能页自定义。历史内容保存在本机 Application Support 目录，文件和视频会优先保存本地副本，超过 1GB 的文件则保留原文件引用以避免占用过多磁盘空间。

macOS 对第三方应用读取其他应用画面强制要求屏幕录制权限，这是系统安全限制。正式发布同样使用 ad-hoc 签名，所以更新流程会主动重置权限，而不是依赖稳定的 Developer ID。

开发期想少授几次权，`build_dev_app.sh` 默认就在找登录钥匙串里名为 `Jarvis Dev Signing` 的自签名证书（找不到会警告并回退 ad-hoc）。没有这张证书时，用和 `install.sh` 相同的办法建一张即可——自签名不需要 Apple 账号，也就不需要那 99 美元：

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

有 Apple Development 证书的话，直接指定也可以：`JARVIS_CODESIGN_IDENTITY="Apple Development: ..." ./build_app.sh`。
