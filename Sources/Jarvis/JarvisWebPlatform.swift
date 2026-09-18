import AppKit
import Foundation
import WebKit

struct JarvisWebPlatformDescriptor: Hashable, Sendable {
    let id: String
    let title: String
    let url: URL
    let allowedHosts: Set<String>

    func allowsHost(_ host: String) -> Bool {
        JarvisWebHostAllowlist.contains(host, in: allowedHosts)
    }
}

enum JarvisWebHostAllowlist {
    static func contains(_ host: String, in allowedHosts: Set<String>) -> Bool {
        let normalized = host.lowercased()
        if allowedHosts.contains(normalized) {
            return true
        }
        return allowedHosts.contains { allowed in
            normalized == allowed || normalized.hasSuffix(".\(allowed)")
        }
    }
}

enum JarvisWebPlatformNavigationDecision: Equatable {
    case allow
    case download
    case openExternally
    case cancel
}

enum JarvisWebPlatformNavigationPolicy {
    static func decision(
        url: URL?,
        isMainFrame: Bool,
        isPrimaryWebView: Bool,
        shouldDownload: Bool,
        allowsHost: (String) -> Bool
    ) -> JarvisWebPlatformNavigationDecision {
        if shouldDownload {
            return .download
        }
        guard let url else {
            return .cancel
        }
        if !isPrimaryWebView || !isMainFrame {
            return .allow
        }
        if isAllowedNavigation(url, allowsHost: allowsHost) {
            return .allow
        }
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            return .openExternally
        }
        return .cancel
    }

    static func isAllowedNavigation(_ url: URL, allowsHost: (String) -> Bool) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return true
        }
        guard scheme == "https", let host = url.host else { return false }
        return allowsHost(host)
    }
}

enum JarvisWebPlatformLayoutMetrics {
    static let topBarSpacing: CGFloat = 12
    static let browserControlSize = JarvisToolbarMetrics.controlSize
    static let browserControlCount = 5
    static let groupedPickerMinimumWidth: CGFloat = 268

    static var actionClusterMinimumWidth: CGFloat {
        (browserControlSize * CGFloat(browserControlCount))
            + 16
    }

    static var minimumTopBarWidth: CGFloat {
        groupedPickerMinimumWidth
            + topBarSpacing
            + actionClusterMinimumWidth
            + 8
    }
}

enum JarvisWebPlatformUserAgent {
    /// WKWebView's default UA omits `Version/x Safari/y`, so sites such as
    /// YouTube live chat treat it as an ancient browser. Append the current
    /// Safari identity while keeping the system's real WebKit tokens.
    static var safariCompatibleApplicationName: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) Safari/605.1.15"
    }
}

enum JarvisWebPlatformConfiguration {
    @MainActor
    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.applicationNameForUserAgent = JarvisWebPlatformUserAgent.safariCompatibleApplicationName
        return configuration
    }
}

enum JarvisWebPlatformFullscreenLayout {
    static let windowedCornerRadius: CGFloat = 16

    static func isActive(_ state: WKWebView.FullscreenState) -> Bool {
        switch state {
        case .enteringFullscreen, .inFullscreen:
            true
        case .exitingFullscreen, .notInFullscreen:
            false
        @unknown default:
            false
        }
    }
}

enum JarvisWebPlaybackPolicy {
    /// 媒体什么时候该暂停。
    ///
    /// 只挂视图的 `onDisappear` 不够：窗口被完全遮挡、最小化、关闭或应用被隐藏时
    /// 视图并不消失，视频会在后台一直解码，GPU 和 `HTMLMediaElement playback`
    /// 的防休眠断言都停不下来。
    ///
    /// 元素全屏是例外：那时网页被移进独立窗口，容器所在窗口的可见性不再代表画面
    /// 状态，不能把用户正在全屏看的视频一起暂停。
    static func shouldSuspendMediaPlayback(
        isSuspendedByView: Bool,
        isHostVisible: Bool,
        isElementFullscreen: Bool
    ) -> Bool {
        if isSuspendedByView {
            return true
        }
        return !isHostVisible && !isElementFullscreen
    }

    /// 全屏的进出过程都算“画面在用户眼前”。
    ///
    /// 退出的那一帧容器所在窗口往往还没恢复可见（全屏窗口还压在上面），按不可见处理
    /// 会把刚退出全屏的视频立刻暂停；等到 `.notInFullscreen` 时遮挡状态已经补上，
    /// 判定自然回到正确值。
    static func isElementFullscreenProtectingPlayback(_ state: WKWebView.FullscreenState) -> Bool {
        switch state {
        case .enteringFullscreen, .inFullscreen, .exitingFullscreen:
            true
        case .notInFullscreen:
            false
        @unknown default:
            false
        }
    }
}

final class JarvisWebPlatformCornerCoverView: NSView {
    var cornerRadius: CGFloat = JarvisWebPlatformFullscreenLayout.windowedCornerRadius {
        didSet {
            if oldValue != cornerRadius {
                needsDisplay = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        clipsToBounds = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_: NSRect) {
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius))
            path.windingRule = .evenOdd
            // Match the SwiftUI floating panel fill so uncovered WKWebView
            // corners do not show as light-gray squares.
            NSColor.controlBackgroundColor.setFill()
            path.fill()

            // 再描一圈圆角。填色用的是面板底色，和网页底色同色时（浅色模式下两边
            // 都是白的）整个圆角就看不出来了，面板看上去是个直角矩形；而面板自己
            // 那圈描边画在网页视图**底下**，被盖住了。这里补上，和
            // `JarvisFloatingPanelModifier` 的描边同一口径（`Color.primary` 8%、
            // 0.75pt，向内描）。
            let border = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.375, dy: 0.375),
                xRadius: cornerRadius - 0.375,
                yRadius: cornerRadius - 0.375
            )
            border.lineWidth = 0.75
            NSColor.labelColor.withAlphaComponent(0.08).setStroke()
            border.stroke()
        }
    }
}

final class JarvisWebPlatformViewContainer: NSView {
    private let cornerCover = JarvisWebPlatformCornerCoverView(frame: .zero)

    /// 宿主画面是否露出。窗口被完全遮挡、最小化、关闭、切到别的空间，或应用被隐藏
    /// 时都是 false。网页媒体只在可见时播放：窗口躲在后台时视频仍会一直解码，
    /// GPU 和 `HTMLMediaElement playback` 的防休眠断言都不会停。
    var onHostVisibilityChange: (@MainActor (Bool) -> Void)? {
        didSet { publishHostVisibility() }
    }

    /// `nonisolated(unsafe)` 只是为了让 `deinit` 能摘掉观察者——`deinit` 是非隔离的，
    /// 而 token 又不是 `Sendable`。实际读写都只在主线程。
    private nonisolated(unsafe) var hostVisibilityObservers: [any NSObjectProtocol] = []
    private var lastPublishedHostVisibility: Bool?

    deinit {
        for observer in hostVisibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeHostWindow()
        publishHostVisibility()
    }

    override func viewDidHide() {
        super.viewDidHide()
        publishHostVisibility()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        publishHostVisibility()
    }

    private var isHostVisible: Bool {
        guard !isHiddenOrHasHiddenAncestor, !NSApplication.shared.isHidden else {
            return false
        }
        guard let window, window.isVisible, !window.isMiniaturized else {
            return false
        }
        return window.occlusionState.contains(.visible)
    }

    private func publishHostVisibility() {
        let isVisible = isHostVisible
        guard lastPublishedHostVisibility != isVisible else {
            return
        }
        lastPublishedHostVisibility = isVisible
        onHostVisibilityChange?(isVisible)
    }

    private func observeHostWindow() {
        for observer in hostVisibilityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        hostVisibilityObservers.removeAll()
        guard let window else {
            return
        }

        let center = NotificationCenter.default
        // `willClose` 的通知是在窗口仍然可见的那一瞬间投递的，直接算会得到“可见”，
        // 而关窗后既不会再发遮挡状态变化、也不会再调 `viewDidMoveToWindow`（实测），
        // 所以它单独处理：等这次关闭落地后再判定。`didBecomeKey`/`didBecomeMain`
        // 补上窗口重新显示的那一侧。
        let windowNotifications: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification
        ]
        for name in windowNotifications {
            hostVisibilityObservers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.publishHostVisibility()
                    }
                }
            )
        }
        hostVisibilityObservers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.publishHostVisibility()
                }
            }
        )
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            hostVisibilityObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.publishHostVisibility()
                    }
                }
            )
        }
    }

    func embed(_ webView: WKWebView) {
        let isFullscreen = JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState)
        cornerCover.isHidden = isFullscreen
        guard !isFullscreen else {
            return
        }
        if webView.superview !== self {
            addSubview(webView)
            webView.autoresizingMask = [.width, .height]
        }
        // Keep rounded corners as a sibling overlay. Masking the WKWebView
        // itself makes hardware video layers flicker.
        wantsLayer = true
        layer?.masksToBounds = false
        clipsToBounds = false
        syncBackgroundColor()
        if cornerCover.superview !== self {
            addSubview(cornerCover, positioned: .above, relativeTo: webView)
        }
        if webView.frame != bounds {
            webView.frame = bounds
        }
        if cornerCover.frame != bounds {
            cornerCover.frame = bounds
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncBackgroundColor()
        cornerCover.needsDisplay = true
    }

    private func syncBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override func layout() {
        super.layout()
        if cornerCover.superview === self, cornerCover.frame != bounds {
            cornerCover.frame = bounds
        }
        guard let webView = subviews.first(where: { $0 is WKWebView }) as? WKWebView,
              webView.superview === self,
              !JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState),
              webView.frame != bounds
        else {
            return
        }
        webView.frame = bounds
    }
}

enum JarvisWebLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    func applying(_ event: JarvisWebLoadEvent) -> JarvisWebLoadState {
        switch event {
        case .begin, .retry:
            .loading
        case .finish:
            .loaded
        case let .fail(message):
            .failed(message)
        case .reset:
            .idle
        }
    }
}

enum JarvisWebLoadEvent: Equatable {
    case begin
    case finish
    case fail(String)
    case retry
    case reset
}

@MainActor
final class JarvisWebPlatformController: NSObject, ObservableObject {
    let platform: JarvisWebPlatformDescriptor
    let webView: WKWebView
    let webViewContainer = JarvisWebPlatformViewContainer()
    let downloadManager: AIConversationDownloadManager

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var loadState: JarvisWebLoadState = .idle
    @Published private(set) var currentURL: URL?

    var isLoading: Bool {
        loadState == .loading
    }

    var loadError: String? {
        guard case let .failed(message) = loadState else { return nil }
        return message
    }

    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?
    private var popupWebViews: [WKWebView] = []
    private var popupFullscreenObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var loadTimeoutTask: Task<Void, Never>?

    deinit {
        loadTimeoutTask?.cancel()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        fullscreenObservation?.invalidate()
        for observation in popupFullscreenObservations.values {
            observation.invalidate()
        }
    }

    init(
        platform: JarvisWebPlatformDescriptor,
        downloadManager: AIConversationDownloadManager
    ) {
        self.platform = platform
        self.downloadManager = downloadManager

        let configuration = JarvisWebPlatformConfiguration.make()
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = .controlBackgroundColor
        webView.clipsToBounds = false
        webViewContainer.embed(webView)
        webViewContainer.onHostVisibilityChange = { [weak self] isVisible in
            self?.setHostPlaybackVisible(isVisible)
        }
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
        fullscreenObservation = webView.observe(\WKWebView.fullscreenState, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncFullscreenLayout()
            }
        }
        webView.load(URLRequest(url: platform.url))
    }

    func goHome() {
        resetLoadState()
        webView.load(URLRequest(url: platform.url))
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
        if isLoading, webView.isLoading {
            webView.stopLoading()
            finishLoading()
        } else {
            resetLoadState()
            webView.reload()
        }
    }

    private func resetLoadState() {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
        loadState = loadState.applying(.reset)
    }

    private func beginLoading() {
        loadTimeoutTask?.cancel()
        loadState = loadState.applying(.begin)
        loadTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 20_000_000_000)
            } catch {
                return
            }
            guard let self, self.isLoading else { return }
            self.loadState = self.loadState.applying(
                .fail("页面响应时间较长，请检查网络后重试。")
            )
            self.loadTimeoutTask = nil
        }
    }

    private func finishLoading() {
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
        loadState = loadState.applying(.finish)
    }

    private func updateNavigationState() {
        let canGoBack = webView.canGoBack
        let canGoForward = webView.canGoForward
        let currentURL = webView.url
        if self.canGoBack != canGoBack {
            self.canGoBack = canGoBack
        }
        if self.canGoForward != canGoForward {
            self.canGoForward = canGoForward
        }
        if self.currentURL != currentURL {
            self.currentURL = currentURL
        }
    }

    /// 实际生效的暂停状态 = 视图要求暂停 或 宿主不可见。
    private(set) var isMediaSuspended = false
    private var isPlaybackSuspendedByView = false
    private var isHostVisible = true

    /// Same effect as Safari hiding a tab: media pauses, live buffers stay.
    func suspendMediaPlayback() {
        guard !isPlaybackSuspendedByView else {
            return
        }
        isPlaybackSuspendedByView = true
        updateMediaPlaybackSuspension()
    }

    func resumeMediaPlayback() {
        guard isPlaybackSuspendedByView else {
            return
        }
        isPlaybackSuspendedByView = false
        updateMediaPlaybackSuspension()
    }

    /// 窗口被遮挡/最小化/关闭或应用被隐藏时同样暂停：只挂 `onDisappear` 的话，
    /// 躲在后台的窗口会一直解码视频。
    func setHostPlaybackVisible(_ isVisible: Bool) {
        guard isHostVisible != isVisible else {
            return
        }
        isHostVisible = isVisible
        updateMediaPlaybackSuspension()
    }

    private func updateMediaPlaybackSuspension() {
        let shouldSuspend = JarvisWebPlaybackPolicy.shouldSuspendMediaPlayback(
            isSuspendedByView: isPlaybackSuspendedByView,
            isHostVisible: isHostVisible,
            isElementFullscreen: isAnyElementFullscreen
        )
        guard shouldSuspend != isMediaSuspended else {
            return
        }
        isMediaSuspended = shouldSuspend
        setMediaPlaybackSuspended(shouldSuspend)
    }

    /// 暂停是作用在主视图和所有弹窗上的，所以“是否全屏”也得看全部——弹窗里全屏的
    /// 视频同样在用户眼前。
    private var isAnyElementFullscreen: Bool {
        if JarvisWebPlaybackPolicy.isElementFullscreenProtectingPlayback(webView.fullscreenState) {
            return true
        }
        return popupWebViews.contains {
            JarvisWebPlaybackPolicy.isElementFullscreenProtectingPlayback($0.fullscreenState)
        }
    }

    private func setMediaPlaybackSuspended(_ suspended: Bool) {
        webView.setAllMediaPlaybackSuspended(suspended) {}
        for popup in popupWebViews {
            popup.setAllMediaPlaybackSuspended(suspended) {}
        }
    }

    private func syncFullscreenLayout() {
        if JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState) {
            webView.layer?.masksToBounds = false
            webView.clipsToBounds = false
            webView.autoresizingMask = [.width, .height]
            fillFullscreenWindowIfNeeded()
            Task { @MainActor [weak self] in
                self?.fillFullscreenWindowIfNeeded()
            }
        } else {
            webView.layer?.masksToBounds = false
            webView.clipsToBounds = false
            webViewContainer.embed(webView)
        }
        // 进出全屏会改变“宿主是否可见”的判定，跟着重算一次暂停状态。
        updateMediaPlaybackSuspension()
    }

    private func fillFullscreenWindowIfNeeded() {
        guard JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState),
              let contentView = webView.window?.contentView
        else {
            return
        }
        webView.frame = contentView.bounds
    }
}

extension JarvisWebPlatformController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? (webView === self.webView)
        switch JarvisWebPlatformNavigationPolicy.decision(
            url: navigationAction.request.url,
            isMainFrame: isMainFrame,
            isPrimaryWebView: webView === self.webView,
            shouldDownload: navigationAction.shouldPerformDownload,
            allowsHost: platform.allowsHost
        ) {
        case .download:
            downloadManager.enqueue(
                platformTitle: platform.title,
                sourceURL: navigationAction.request.url
            )
            decisionHandler(.download)
        case .allow:
            decisionHandler(.allow)
        case .openExternally:
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        case .cancel:
            decisionHandler(.cancel)
        }
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            downloadManager.enqueue(
                platformTitle: platform.title,
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
            platformTitle: platform.title,
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
            platformTitle: platform.title,
            sourceURL: navigationResponse.response.url
        )
    }

    func webView(_: WKWebView, didStartProvisionalNavigation _: WKNavigation?) {
        beginLoading()
        updateNavigationState()
    }

    func webView(_: WKWebView, didFinish _: WKNavigation?) {
        finishLoading()
        updateNavigationState()
    }

    func webView(
        _: WKWebView,
        didFailProvisionalNavigation _: WKNavigation?,
        withError error: Error
    ) {
        finishLoading()
        if !Self.isCancellation(error) {
            loadState = loadState.applying(.fail(error.localizedDescription))
        }
        updateNavigationState()
    }

    func webView(
        _: WKWebView,
        didFail _: WKNavigation?,
        withError error: Error
    ) {
        finishLoading()
        if !Self.isCancellation(error) {
            loadState = loadState.applying(.fail(error.localizedDescription))
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
}

extension JarvisWebPlatformController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url,
               JarvisWebPlatformNavigationPolicy.isAllowedNavigation(url, allowsHost: platform.allowsHost)
            {
                webView.load(navigationAction.request)
            } else if let url = navigationAction.request.url,
                      url.scheme == "http" || url.scheme == "https"
            {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        configuration.preferences.isElementFullscreenEnabled = true
        configuration.applicationNameForUserAgent = JarvisWebPlatformUserAgent.safariCompatibleApplicationName
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.autoresizingMask = [.width, .height]
        popup.underPageBackgroundColor = .controlBackgroundColor
        popup.clipsToBounds = false
        webView.addSubview(popup)
        popupWebViews.append(popup)
        popupFullscreenObservations[ObjectIdentifier(popup)] = popup.observe(
            \WKWebView.fullscreenState,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.updateMediaPlaybackSuspension()
            }
        }
        if isMediaSuspended {
            popup.setAllMediaPlaybackSuspended(true) {}
        }
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        webView.removeFromSuperview()
        popupWebViews.removeAll { $0 === webView }
        popupFullscreenObservations[ObjectIdentifier(webView)]?.invalidate()
        popupFullscreenObservations[ObjectIdentifier(webView)] = nil
    }

    func webView(
        _: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame _: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
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
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let protocolName = origin.protocol.lowercased()
        let host = origin.host.lowercased()
        guard protocolName == "https", platform.allowsHost(host) else {
            JarvisLog.notice(
                category: .security,
                event: "web.mediaCapture.permission.denied",
                result: "untrustedOrigin",
                fields: [
                    "platform": platform.id,
                    "protocol": protocolName,
                    "host": host
                ]
            )
            decisionHandler(.deny)
            return
        }

        JarvisLog.info(
            category: .security,
            event: "web.mediaCapture.permission.requested",
            fields: [
                "platform": platform.id,
                "protocol": protocolName,
                "host": host,
                "type": String(describing: type)
            ]
        )

        Task { @MainActor [weak self] in
            guard let self else {
                decisionHandler(.deny)
                return
            }

            let granted = await requestSystemMediaAccess(for: type)
            JarvisLog.info(
                category: .security,
                event: "web.mediaCapture.permission.complete",
                result: granted ? "granted" : "denied",
                fields: [
                    "platform": platform.id,
                    "protocol": protocolName,
                    "host": host,
                    "type": String(describing: type)
                ]
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
