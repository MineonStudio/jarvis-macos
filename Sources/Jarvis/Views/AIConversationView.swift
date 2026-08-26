import AppKit
import SwiftUI
import WebKit

enum AIConversationProvider: String, CaseIterable, Hashable, Identifiable {
    case deepSeek = "deepseek"
    case gpt
    case doubao
    case grok

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .gpt: "ChatGPT"
        case .doubao: "豆包"
        case .grok: "Grok"
        }
    }

    var iconResourceName: String {
        rawValue
    }

    var iconResourceExtension: String {
        switch self {
        case .doubao: "png"
        case .deepSeek, .gpt, .grok: "svg"
        }
    }

    var selectedIconResourceName: String? {
        switch self {
        case .deepSeek: "deepseek-selected"
        case .gpt: "gpt-selected"
        case .doubao: nil
        case .grok: "grok-selected"
        }
    }

    var url: URL {
        switch self {
        case .deepSeek:
            URL(string: "https://chat.deepseek.com/")!
        case .gpt:
            URL(string: "https://chatgpt.com/")!
        case .doubao:
            URL(string: "https://www.doubao.com/chat/")!
        case .grok:
            URL(string: "https://grok.com/")!
        }
    }
}

enum AIConversationLayoutMetrics {
    static let providerIconWidth: CGFloat = 18
    static let providerItemSpacing: CGFloat = 7
    static let providerItemHorizontalPadding: CGFloat = 24
    static let providerNavigationItemSpacing: CGFloat = 2
    static let providerNavigationPadding: CGFloat = 4
    static let topBarSpacing: CGFloat = 12
    static let browserControlSize: CGFloat = 32
    static let browserControlSpacing: CGFloat = 8
    static let browserControlCount = 4

    static var providerNavigationMinimumWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let itemWidth = AIConversationProvider.allCases.reduce(CGFloat.zero) { width, provider in
            let titleWidth = (provider.title as NSString)
                .size(withAttributes: [.font: font])
                .width
            return width
                + providerIconWidth
                + providerItemSpacing
                + titleWidth
                + providerItemHorizontalPadding
        }
        let itemSpacing = providerNavigationItemSpacing
            * CGFloat(max(0, AIConversationProvider.allCases.count - 1))
        return ceil(itemWidth + itemSpacing + providerNavigationPadding + 8)
    }

    static var browserControlsMinimumWidth: CGFloat {
        (browserControlSize * CGFloat(browserControlCount))
            + (browserControlSpacing * CGFloat(browserControlCount - 1))
            + 8
    }

    static var minimumTopBarWidth: CGFloat {
        providerNavigationMinimumWidth + topBarSpacing + browserControlsMinimumWidth
    }
}

@MainActor
final class AIConversationWebController: NSObject, ObservableObject {
    let provider: AIConversationProvider
    let webView: WKWebView
    let downloadManager: AIConversationDownloadManager

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    init(
        provider: AIConversationProvider,
        downloadManager: AIConversationDownloadManager
    ) {
        self.provider = provider
        self.downloadManager = downloadManager

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        canGoBackObservation = webView.observe(\WKWebView.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateNavigationState()
            }
        }
        canGoForwardObservation = webView.observe(\WKWebView.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateNavigationState()
            }
        }
        webView.load(URLRequest(url: provider.url))
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
        updateNavigationState()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
        updateNavigationState()
    }

    func reloadOrStop() {
        if webView.isLoading {
            webView.stopLoading()
            isLoading = false
        } else {
            loadError = nil
            webView.reload()
        }
    }

    private func updateNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

extension AIConversationWebController: WKNavigationDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            downloadManager.enqueue(
                provider: provider,
                sourceURL: navigationAction.request.url
            )
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            downloadManager.enqueue(
                provider: provider,
                sourceURL: navigationResponse.response.url
            )
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(
        _: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadManager.attach(
            download,
            provider: provider,
            sourceURL: navigationAction.request.url
        )
    }

    func webView(
        _: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadManager.attach(
            download,
            provider: provider,
            sourceURL: navigationResponse.response.url
        )
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation?) {
        isLoading = true
        loadError = nil
        updateNavigationState()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation?) {
        isLoading = false
        updateNavigationState()
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation?,
        withError error: Error
    ) {
        isLoading = false
        loadError = error.localizedDescription
        updateNavigationState()
    }

    func webView(
        _: WKWebView,
        didFail _: WKNavigation?,
        withError error: Error
    ) {
        isLoading = false
        loadError = error.localizedDescription
        updateNavigationState()
    }
}

extension AIConversationWebController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        webView.load(navigationAction.request)
        return nil
    }

    func webView(
        _: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}

struct AIConversationView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        AIConversationBrowserPage(
            controller: currentController
        )
        .id(app.selectedAIProvider)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var currentController: AIConversationWebController {
        app.aiConversationController(for: app.selectedAIProvider)
    }
}

struct AIConversationTopBar: View {
    @EnvironmentObject private var app: AppModel
    @State private var showsDownloadManager = false

    var body: some View {
        JarvisTopBarContainer {
            HStack(spacing: AIConversationLayoutMetrics.topBarSpacing) {
                AIConversationProviderNavigation(selection: $app.selectedAIProvider)
                Spacer(minLength: 0)
                AIConversationBrowserControls(
                    controller: currentController,
                    showsDownloadManager: $showsDownloadManager
                )
            }
            .frame(minWidth: AIConversationLayoutMetrics.minimumTopBarWidth)
        }
    }

    private var currentController: AIConversationWebController {
        app.aiConversationController(for: app.selectedAIProvider)
    }
}

private struct AIConversationProviderNavigation: View {
    @Binding var selection: AIConversationProvider

    var body: some View {
        JarvisSegmentedControl(
            items: Array(AIConversationProvider.allCases),
            selection: $selection
        ) { provider, isSelected in
            HStack(spacing: 7) {
                AIConversationProviderIcon(provider: provider, isSelected: isSelected)
                Text(provider.title)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(
                minHeight: JarvisMetrics.segmentedItemHeight,
                maxHeight: JarvisMetrics.segmentedItemHeight
            )
            .padding(.horizontal, 12)
            .padding(.vertical, JarvisMetrics.topNavigationVerticalPadding)
            .help(provider.title)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 20, y: 9)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct AIConversationProviderIcon: View {
    let provider: AIConversationProvider
    let isSelected: Bool

    var body: some View {
        Group {
            if let image = Self.image(for: provider, isSelected: isSelected) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private static func image(
        for provider: AIConversationProvider,
        isSelected: Bool
    ) -> NSImage? {
        let resourceName = isSelected
            ? (provider.selectedIconResourceName ?? provider.iconResourceName)
            : provider.iconResourceName
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: provider.iconResourceExtension,
            subdirectory: "AIProviderIcons"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.isTemplate = false
        return image
    }
}

private struct AIConversationBrowserControls: View {
    @ObservedObject var controller: AIConversationWebController
    @Binding var showsDownloadManager: Bool

    var body: some View {
        HStack(spacing: 8) {
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
            downloadManagerButton
        }
    }

    private var downloadManagerButton: some View {
        Button {
            showsDownloadManager.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())

                if controller.downloadManager.activeDownloadCount > 0 {
                    Text("\(controller.downloadManager.activeDownloadCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .foregroundStyle(Color.secondary)
        .jarvisGlass(in: Circle(), interactive: true)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
        .help("下载管理")
        .popover(isPresented: $showsDownloadManager, arrowEdge: .top) {
            AIConversationDownloadManagerView(manager: controller.downloadManager)
                .frame(width: 390, height: 390)
        }
    }

    private func browserControlButton(
        systemName: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
        help: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.76))
        .foregroundStyle(Color.secondary)
        .opacity(isDisabled ? 0.38 : 1)
        .disabled(isDisabled)
        .jarvisGlass(in: Circle(), interactive: true)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
        .help(help)
    }
}

private struct AIConversationDownloadManagerView: View {
    @ObservedObject var manager: AIConversationDownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("下载管理")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if manager.hasDownloads {
                    Button("清理已完成") {
                        manager.clearFinished()
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11, weight: .medium))
                }
            }
            .padding(.bottom, 12)

            if manager.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("还没有下载任务")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text("在聊天页面点击文件下载后，任务会显示在这里")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.items) { item in
                            AIConversationDownloadRow(item: item, manager: manager)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }

            Divider()
                .padding(.top, 12)

            Button {
                manager.openDownloadsFolder()
            } label: {
                Label("打开下载文件夹", systemImage: "folder")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
            .foregroundStyle(Color.accentColor)
            .padding(.top, 10)
        }
        .padding(16)
    }
}

private struct AIConversationDownloadRow: View {
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
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text("\(item.provider.title) · \(item.state.title)")
                    if let errorMessage = item.errorMessage {
                        Text(errorMessage)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
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
                .font(.system(size: 11, weight: .medium))
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

private struct AIConversationBrowserPage: View {
    @ObservedObject var controller: AIConversationWebController

    var body: some View {
        ZStack {
            AIConversationWebView(controller: controller)

            if let loadError = controller.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("\(controller.provider.title) 页面加载失败")
                        .font(.system(size: 15, weight: .semibold))
                    Text(loadError)
                        .font(.system(size: 12))
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .jarvisFloatingPanel(cornerRadius: 16)
    }
}

private struct AIConversationWebView: NSViewRepresentable {
    @ObservedObject var controller: AIConversationWebController

    func makeNSView(context _: Context) -> WKWebView {
        let webView = controller.webView
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 16
        webView.layer?.masksToBounds = true
        return webView
    }

    func updateNSView(_ _: WKWebView, context _: Context) {}
}
