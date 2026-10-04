# 贾维斯

<img src="docs/icon.png" width="96" alt="贾维斯">

macOS 菜单栏工具。截图、剪贴板、会议记录、壁纸，另外有窗口布局和简历。

macOS 26 及以上。

## 安装

[下载最新版](https://github.com/MineonStudio/jarvis-macos/releases/latest)，打开 DMG，把 Jarvis.app 拖进「应用程序」。

或者：

```bash
curl -fsSL https://raw.githubusercontent.com/MineonStudio/jarvis-macos/dev/install.sh | zsh
```

脚本会下载发布包，在登录钥匙串里生成一张「Jarvis Local Signing」证书，签完名再安装。证书只留在这台 Mac 上。之后更新时，屏幕录制、辅助功能、麦克风和摄像头可以沿用。钥匙串仍可能再问一次。

卸载：

```bash
curl -fsSL https://raw.githubusercontent.com/MineonStudio/jarvis-macos/dev/install.sh | zsh -s -- --uninstall
```

从 DMG 拖进去的包没有这张证书。第一次打开时，权限页可以补上同样的签名。

## 快捷键

| 按键 | 作用 |
| --- | --- |
| F1 | 截图 |
| F2 | 剪贴板 |
| F3 | 开始或停止会议录音 |

都可以在设置里改。剪贴板面板里，⌘1–9 或回车会粘贴。

## 里面有什么

- 截图。框选，或点一个窗口。图留在原地，可以画箭头、打马赛克、写字，然后复制或另存。
- 剪贴板。文本、图片、文件、视频。可以筛选、搜索、收藏。超过 1GB 的文件只记住原路径。
- 会议记录。麦克风和系统声音留在本机，转写也在本机。总结用设置里填的模型。第一次用要先下载本地识别模型。
- 桌面壁纸、窗口布局、简历制作。
- AI 聚合、娱乐广场。在应用里打开的网页。

截图、剪贴板、录音和逐字稿都在本机。会议总结和截图翻译会把内容发给设置里的服务。

截图需要允许「屏幕与系统音频录制」。会议需要麦克风。

## 从源码构建

```bash
./build_app.sh
open dist/Jarvis.app
```

开发版是 `./build_dev_app.sh`，产物是 `dist/Jarvis-Dev.app`。证书写在 [docs/build.md](docs/build.md)。发版见 [docs/update-release.md](docs/update-release.md)。
