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

    var allowedHosts: Set<String> {
        switch self {
        case .deepSeek:
            ["chat.deepseek.com", "deepseek.com", "www.deepseek.com"]
        case .gpt:
            ["chatgpt.com", "www.chatgpt.com", "chat.openai.com", "openai.com", "www.openai.com"]
        case .doubao:
            ["www.doubao.com", "doubao.com", "www.volcengine.com"]
        case .grok:
            ["grok.com", "www.grok.com", "x.ai", "www.x.ai"]
        }
    }

    func allowsHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if allowedHosts.contains(normalized) {
            return true
        }
        return allowedHosts.contains { allowed in
            normalized == allowed || normalized.hasSuffix(".\(allowed)")
        }
    }
}

enum AIConversationLayoutMetrics {
    static let topBarSpacing: CGFloat = 12
    static let browserControlSize = JarvisToolbarMetrics.controlSize
    static let browserControlSpacing = JarvisToolbarMetrics.controlSpacing
    static let browserControlCount = 4

    static var browserControlsMinimumWidth: CGFloat {
        (browserControlSize * CGFloat(browserControlCount))
            + (browserControlSpacing * CGFloat(browserControlCount - 1))
            + 8
    }

    static var minimumTopBarWidth: CGFloat {
        browserControlsMinimumWidth + topBarSpacing + browserControlSize + 8
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

    func goHome() {
        loadError = nil
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
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if Self.isAllowedNavigation(url, for: provider) {
            decisionHandler(.allow)
        } else if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.cancel)
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
        if !Self.isCancellation(error) {
            loadError = error.localizedDescription
        }
        updateNavigationState()
    }

    func webView(
        _: WKWebView,
        didFail _: WKNavigation?,
        withError error: Error
    ) {
        isLoading = false
        if !Self.isCancellation(error) {
            loadError = error.localizedDescription
        }
        updateNavigationState()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        return nsError.domain == "WebKitErrorDomain" && nsError.code == 102
    }

    private static func isAllowedNavigation(_ url: URL, for provider: AIConversationProvider) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return true
        }
        guard scheme == "https", let host = url.host else { return false }
        return provider.allowsHost(host)
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
        guard let url = navigationAction.request.url else { return nil }
        if Self.isAllowedNavigation(url, for: provider) {
            webView.load(navigationAction.request)
        } else if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
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

    func webView(
        _: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame _: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let protocolName = origin.protocol.lowercased()
        let host = origin.host.lowercased()
        guard protocolName == "https", provider.allowsHost(host) else {
            NSLog("Jarvis denied media capture for untrusted origin: %@://%@", protocolName, host)
            decisionHandler(.deny)
            return
        }

        NSLog(
            "Jarvis requesting media capture permission for provider=%@ origin=%@://%@ type=%@",
            provider.rawValue,
            protocolName,
            host,
            String(describing: type)
        )

        Task { @MainActor [weak self] in
            guard let self else {
                decisionHandler(.deny)
                return
            }

            let granted = await requestSystemMediaAccess(for: type)
            NSLog(
                "Jarvis media capture permission result provider=%@ origin=%@://%@ granted=%@",
                provider.rawValue,
                protocolName,
                host,
                granted ? "true" : "false"
            )
            decisionHandler(granted ? .grant : .deny)
        }
    }

    private func requestSystemMediaAccess(for type: WKMediaCaptureType) async -> Bool {
        let requiresMicrophone = type == .microphone || type == .cameraAndMicrophone
        let requiresCamera = type == .camera || type == .cameraAndMicrophone

        var microphoneGranted = true
        if requiresMicrophone {
            microphoneGranted = await JarvisPrivacyPermissionAccess.requestMediaAccess(for: .audio)
        }

        var cameraGranted = true
        if requiresCamera {
            cameraGranted = await JarvisPrivacyPermissionAccess.requestMediaAccess(for: .video)
        }

        return microphoneGranted && cameraGranted
    }
}

struct AIConversationView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showsDownloadManager = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    AIConversationBrowserControls(
                        controller: currentController
                    )
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    AIConversationDownloadButton(
                        controller: currentController,
                        showsDownloadManager: $showsDownloadManager
                    )
                }
            },
            content: {
                AIConversationBrowserPage(
                    controller: currentController
                )
                .id(app.selectedAIProvider)
            }
        )
    }

    private var currentController: AIConversationWebController {
        app.aiConversationController(for: app.selectedAIProvider)
    }
}

struct AIConversationProviderIcon: View {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: JarvisToolbarMetrics.controlSpacing) {
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
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: controller.isLoading
        )
    }
}

private struct AIConversationDownloadButton: View {
    @ObservedObject var controller: AIConversationWebController
    @Binding var showsDownloadManager: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            showsDownloadManager.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.down")
                    .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))

                if controller.downloadManager.activeDownloadCount > 0 {
                    Text("\(controller.downloadManager.activeDownloadCount)")
                        .font(JarvisTypography.badge)
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 4, y: -4)
                        .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
                }
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .foregroundStyle(Color.secondary)
        .help("下载管理")
        .animation(
            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
            value: controller.downloadManager.activeDownloadCount
        )
        .popover(isPresented: $showsDownloadManager, arrowEdge: .top) {
            AIConversationDownloadManagerView(manager: controller.downloadManager)
                .frame(width: 390, height: 390)
        }
    }
}

private extension AIConversationBrowserControls {
    func browserControlButton(
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

private struct AIConversationDownloadManagerView: View {
    @ObservedObject var manager: AIConversationDownloadManager
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
                    Text("在聊天页面点击文件下载后，任务会显示在这里")
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
                            AIConversationDownloadRow(item: item, manager: manager)
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
                    .font(JarvisTypography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Text("\(item.provider.title) · \(item.state.title)")
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

private struct AIConversationBrowserPage: View {
    @ObservedObject var controller: AIConversationWebController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AIConversationWebView(controller: controller)

            if let loadError = controller.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("\(controller.provider.title) 页面加载失败")
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .jarvisFloatingPanel(cornerRadius: 16)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: controller.loadError
        )
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
