# 贾维斯

公开仓库：[MineonStudio/jarvis-macos](https://github.com/MineonStudio/jarvis-macos)

一个 API 驱动、可更换大脑、可扩展技能的 macOS AI 工具人。

## 当前 MVP

- SwiftUI 原生 macOS 应用外壳
- OpenAI-compatible API 配置
- API Key 保存到 macOS Keychain
- 设置中支持跟随系统、浅色和深色主题
- 框选截图
- ScreenCaptureKit 单帧抓取 + 自定义全屏暗幕、窗口命中和框选
- 截图后在原屏幕位置保留，截图窗口和工具栏独立分离且可一起拖动
- 箭头绘制、马赛克像素化、文本输入
- 标注撤销/重做
- 编辑后的截图另存为、复制和完成编辑
- 截图编辑器内自动翻译当前截图选区，支持原文区域高斯模糊、译文回填、目标语言选择和双语截图保存
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

版本号会显示在设置页的“版本与更新”区域。发布新版本时使用 `v主版本.次版本.修订版本` 标签，并在 GitHub Releases 创建正式版本；设置页可检查 GitHub Releases 是否有新版本。点击“下载更新”后，Jarvis 会先在当前进程中清除旧的屏幕录制权限，再继续下载和安装。

截图快捷键触发后，Jarvis 会先用 ScreenCaptureKit 冻结所有显示器画面，再显示自己的暗幕。悬停窗口会高亮，单击即可截取整个应用窗口；拖动则可以自定义框选区域，不会打开 macOS 的“共享整个屏幕”选择器。如果 macOS 要求授权，请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许贾维斯访问屏幕。Jarvis 当前只请求屏幕画面，不启用系统音频或麦克风捕获。

截图编辑器中的“翻译”会把当前选区的最终图像一次发送给支持视觉输入的 OpenAI-compatible 模型，由大模型直接识别并翻译文字，同时返回每个原文区域的左上角归一化坐标。客户端严格复用模型返回的原文框覆盖绘制译文，不根据译文重新计算位置；翻译完成后会在对应原文区域应用高斯模糊，并根据该区域的原文行高与自然宽度估算匹配字号。如果译文在对应原区域内放不下，会逐步缩小字体；模型未返回完整 JSON 分块结果时不会渲染不确定的统一译文。翻译不会弹出独立面板，结果直接回到截图编辑器中，并可继续确认、复制或保存。

截图快捷键默认为 F1，剪贴板历史默认使用 F2 唤起独立面板，两个快捷键都可以在对应技能页自定义。历史内容保存在本机 Application Support 目录，文件和视频会优先保存本地副本，超过 1GB 的文件则保留原文件引用以避免占用过多磁盘空间。

macOS 对第三方应用读取其他应用画面强制要求屏幕录制权限，这是系统安全限制。使用临时 ad-hoc 签名开发时，每次重建可能产生新的代码身份并要求重新允许；如果本机有 Apple Development 签名，可这样构建以保持权限身份：

```bash
JARVIS_CODESIGN_IDENTITY="Apple Development: ..." ./build_app.sh
```
