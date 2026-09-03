import AppKit
import SwiftUI
import WebKit

struct JarvisToolbarGroupedPicker<Item: Identifiable & Hashable, Icon: View>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item, Bool) -> Icon

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 6) {
                        icon(item, isSelected)
                            .frame(width: 16, height: 16)
                        Text(title(item))
                            .font(isSelected ? JarvisTypography.controlEmphasis : JarvisTypography.control)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background {
                        Capsule()
                            .fill(JarvisMotion.selectionPillTint)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                .help(title(item))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: JarvisToolbarMetrics.controlSize)
        // The enclosing ToolbarItem supplies the native toolbar group surface.
        // Do not add a second custom glass capsule inside it.
    }
}

struct JarvisWebPlatformActionCluster<DownloadPopover: View>: View {
    @ObservedObject var controller: JarvisWebPlatformController
    @Binding var showsDownloadManager: Bool
    var activeDownloadCount: Int
    var downloadHelp: String = "下载管理"
    @ViewBuilder var downloadPopover: () -> DownloadPopover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            browserControlButton(
                systemName: "house",
                action: controller.goHome,
                help: "主页"
            )
            browserControlButton(
                systemName: "chevron.left",
                action: controller.goBack,
                isDisabled: !controller.canGoBack,
                help: "后退"
            )
            browserControlButton(
                systemName: "chevron.right",
                action: controller.goForward,
                isDisabled: !controller.canGoForward,
                help: "前进"
            )
            browserControlButton(
                systemName: controller.isLoading ? "xmark" : "arrow.clockwise",
                action: controller.reloadOrStop,
                help: controller.isLoading ? "停止加载" : "刷新"
            )
            JarvisWebPlatformDownloadButton(
                activeDownloadCount: activeDownloadCount,
                showsDownloadManager: $showsDownloadManager,
                help: downloadHelp,
                popover: downloadPopover
            )
        }
        .padding(3)
        .frame(height: JarvisToolbarMetrics.controlSize)
        // The enclosing ToolbarItem supplies the native toolbar group surface.
        // Do not add a second custom glass capsule inside it.
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: controller.isLoading
        )
    }

    private func browserControlButton(
        systemName: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
        help: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .foregroundStyle(Color.secondary)
        .opacity(isDisabled ? 0.38 : 1)
        .disabled(isDisabled)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
        .help(help)
    }
}

struct JarvisWebPlatformDownloadButton<Popover: View>: View {
    let activeDownloadCount: Int
    @Binding var showsDownloadManager: Bool
    var help: String = "下载管理"
    @ViewBuilder var popover: () -> Popover
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            showsDownloadManager.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.down")
                    .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))

                if activeDownloadCount > 0 {
                    Text("\(activeDownloadCount)")
                        .font(JarvisTypography.badge)
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 4, y: -4)
                        .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                }
            }
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .foregroundStyle(Color.secondary)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
        .help(help)
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: activeDownloadCount
        )
        .popover(isPresented: $showsDownloadManager, arrowEdge: .top) {
            popover()
        }
    }
}

struct JarvisWebPlatformDownloadManagerView: View {
    @ObservedObject var manager: AIConversationDownloadManager
    let emptyHint: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("下载管理")
                    .font(JarvisTypography.cardTitle)
                Spacer()
                if manager.hasDownloads {
                    Button("清理已完成") {
                        manager.clearFinished()
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                    .foregroundStyle(Color.accentColor)
                    .font(JarvisTypography.control)
                }
            }
            .padding(.bottom, 12)

            if manager.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("还没有下载任务")
                        .font(JarvisTypography.bodyEmphasis)
                        .foregroundStyle(Color.secondary)
                    Text(emptyHint)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.items) { item in
                            JarvisWebPlatformDownloadRow(item: item, manager: manager)
                                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                        }
                    }
                    .animation(
                        JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
                        value: manager.items.count
                    )
                }
                .scrollIndicators(.automatic)
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }

            Divider()
                .padding(.top, 12)

            Button {
                manager.openDownloadsFolder()
            } label: {
                Label("打开下载文件夹", systemImage: "folder")
                    .font(JarvisTypography.control)
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
            .foregroundStyle(Color.accentColor)
            .padding(.top, 10)
        }
        .padding(16)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: manager.items.count
        )
    }
}

private struct JarvisWebPlatformDownloadRow: View {
    let item: AIConversationDownloadItem
    @ObservedObject var manager: AIConversationDownloadManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.state.icon)
                .foregroundStyle(stateColor)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.filename)
                    .font(JarvisTypography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text("\(item.platformTitle) · \(item.state.title)")
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .lineLimit(1)
                    }
                }
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.secondary)

                if item.state == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 4)

            if item.state.isActive {
                Button("取消") {
                    manager.cancel(item)
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.secondary)
            } else if item.canOpenFile {
                Menu {
                    Button("打开文件") {
                        manager.open(item)
                    }
                    Button("在 Finder 中显示") {
                        manager.revealInFinder(item)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(10)
        .background(Color.jarvisPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }

    private var stateColor: Color {
        switch item.state {
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        case .queued, .downloading: .accentColor
        }
    }
}

struct JarvisWebPlatformBrowserPage: View {
    @ObservedObject var controller: JarvisWebPlatformController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            JarvisWebPlatformWebView(controller: controller)
                .equatable()

            if let loadError = controller.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("\(controller.platform.title) 页面加载失败")
                        .font(JarvisTypography.cardTitle)
                    Text(loadError)
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    Button("重新加载") {
                        controller.reloadOrStop()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(28)
                .frame(maxWidth: 420)
                .jarvisGlass(cornerRadius: JarvisMetrics.cardRadius, interactive: false)
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .jarvisFloatingPanel(cornerRadius: 16)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: controller.loadError
        )
    }
}

private struct JarvisWebPlatformWebView: NSViewRepresentable, Equatable {
    let controller: JarvisWebPlatformController

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.controller === rhs.controller
    }

    func makeNSView(context _: Context) -> JarvisWebPlatformViewContainer {
        let container = controller.webViewContainer
        container.embed(controller.webView)
        return container
    }

    func updateNSView(_ container: JarvisWebPlatformViewContainer, context _: Context) {
        container.embed(controller.webView)
    }
}
