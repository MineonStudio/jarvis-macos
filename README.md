# 贾维斯

公开仓库：[MineonStudio/jarvis-macos](https://github.com/MineonStudio/jarvis-macos)

一个 API 驱动、可更换大脑、可扩展技能的 macOS AI 工具人。

## 当前 MVP

- SwiftUI 原生 macOS 应用外壳
- OpenAI-compatible API 配置
- API Key 保存到 macOS Keychain
- 框选截图
- Apple 系统显示器选择器 + ScreenCaptureKit 单帧抓取，随后进入全屏暗幕与自定义框选
- 截图后在原屏幕位置保留，截图窗口和工具栏独立分离且可一起拖动
- 箭头绘制、马赛克像素化、文本输入
- 标注撤销/重做
- 编辑后的截图另存为、复制和完成编辑
- 截图翻译入口
- 翻译结果悬浮到屏幕
- 剪贴板历史记录，支持文本、图片、文件和视频
- 剪贴板独立面板（默认 F2）、类型筛选、收藏、搜索与快捷粘贴（⌘1–9 / 回车）
- 菜单栏常驻入口

## 构建

```bash
./build_app.sh
open dist/Jarvis.app
```

升级时保持同一个 `com.jarvis.mac` Bundle ID 和 `dist/Jarvis.app` 路径，只递增版本号：

```bash
JARVIS_VERSION="0.1.2" JARVIS_BUILD="3" ./build_app.sh
```

版本号会显示在设置页的“版本与更新”区域。发布新版本时使用 `v主版本.次版本.修订版本` 标签，并在 GitHub Releases 创建正式版本；设置页可检查 GitHub Releases 是否有新版本。

首次使用截图时，Jarvis 会打开 macOS 系统显示器选择器并缓存你的选择；后续截图会直接复用该显示器，不会重复打开共享界面。需要切换显示器时，可从菜单栏选择“重新选择截图显示器”。如果 macOS 要求授权，请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许贾维斯访问屏幕。Jarvis 当前只请求屏幕画面，不启用系统音频或麦克风捕获。

截图快捷键默认为 F1，剪贴板历史默认使用 F2 唤起独立面板，两个快捷键都可以在对应技能页自定义。历史内容保存在本机 Application Support 目录，文件和视频会优先保存本地副本，超过 1GB 的文件则保留原文件引用以避免占用过多磁盘空间。

macOS 对第三方应用读取其他应用画面强制要求屏幕录制权限，这是系统安全限制。使用临时 ad-hoc 签名开发时，每次重建可能产生新的代码身份并要求重新允许；如果本机有 Apple Development 签名，可这样构建以保持权限身份：

```bash
JARVIS_CODESIGN_IDENTITY="Apple Development: ..." ./build_app.sh
```
