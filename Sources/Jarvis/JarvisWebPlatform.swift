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

typealias AIConversationNavigationDecision = JarvisWebPlatformNavigationDecision

enum AIConversationNavigationPolicy {
    static func decision(
        url: URL?,
        isMainFrame: Bool,
        isPrimaryWebView: Bool,
        shouldDownload: Bool,
        provider: AIConversationProvider
    ) -> AIConversationNavigationDecision {
        JarvisWebPlatformNavigationPolicy.decision(
            url: url,
            isMainFrame: isMainFrame,
            isPrimaryWebView: isPrimaryWebView,
            shouldDownload: shouldDownload,
            allowsHost: provider.allowsHost
        )
    }

    static func isAllowedNavigation(_ url: URL, for provider: AIConversationProvider) -> Bool {
        JarvisWebPlatformNavigationPolicy.isAllowedNavigation(url, allowsHost: provider.allowsHost)
    }
}

enum JarvisWebPlatformLayoutMetrics {
    static let topBarSpacing: CGFloat = 12
    static let browserControlSize = JarvisToolbarMetrics.controlSize
    static let browserControlSpacing = JarvisToolbarMetrics.controlSpacing
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

final class JarvisWebPlatformViewContainer: NSView {
    func embed(_ webView: WKWebView) {
        guard !JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState) else { return }
        if webView.superview !== self {
            addSubview(webView)
        }
        wantsLayer = true
        layer?.cornerRadius = JarvisWebPlatformFullscreenLayout.windowedCornerRadius
        layer?.masksToBounds = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
    }

    override func layout() {
        super.layout()
        guard let webView = subviews.first as? WKWebView,
              webView.superview === self,
              !JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState)
        else {
            return
        }
        webView.frame = bounds
    }
}

typealias AIConversationLayoutMetrics = JarvisWebPlatformLayoutMetrics

@MainActor
final class JarvisWebPlatformController: NSObject, ObservableObject {
    let platform: JarvisWebPlatformDescriptor
    let webView: WKWebView
    let webViewContainer = JarvisWebPlatformViewContainer()
    let downloadManager: AIConversationDownloadManager

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var currentURL: URL?

    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var fullscreenObservation: NSKeyValueObservation?
    private var popupWebViews: [WKWebView] = []

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
        webViewContainer.embed(webView)
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
        loadError = nil
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
        currentURL = webView.url
    }

    private(set) var isMediaSuspended = false

    // tab 切走时原生挂起全部媒体（含 Web Audio），不触碰页面 DOM：
    // 网络/缓冲照常（直播不丢），切回时 setAllMediaPlaybackSuspended(false)
    // 会从原位置自动续播，效果等同 Safari 隐藏标签页
    func suspendMediaPlayback() {
        guard !isMediaSuspended else { return }
        isMediaSuspended = true
        webView.setAllMediaPlaybackSuspended(true) {}
    }

    func resumeMediaPlayback() {
        guard isMediaSuspended else { return }
        isMediaSuspended = false
        webView.setAllMediaPlaybackSuspended(false) {}
    }

    private func syncFullscreenLayout() {
        if JarvisWebPlatformFullscreenLayout.isActive(webView.fullscreenState) {
            webView.layer?.cornerRadius = 0
            webView.layer?.masksToBounds = false
            webView.autoresizingMask = [.width, .height]
            fillFullscreenWindowIfNeeded()
            Task { @MainActor [weak self] in
                self?.fillFullscreenWindowIfNeeded()
            }
        } else {
            webView.layer?.cornerRadius = 0
            webView.layer?.masksToBounds = false
            webViewContainer.embed(webView)
        }
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
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
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
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
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
        popup.underPageBackgroundColor = .clear
        webView.addSubview(popup)
        popupWebViews.append(popup)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        webView.removeFromSuperview()
        popupWebViews.removeAll { $0 === webView }
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
        guard protocolName == "https", platform.allowsHost(host) else {
            NSLog("Jarvis denied media capture for untrusted origin: %@://%@", protocolName, host)
            decisionHandler(.deny)
            return
        }

        NSLog(
            "Jarvis requesting media capture permission for platform=%@ origin=%@://%@ type=%@",
            platform.id,
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
                "Jarvis media capture permission result platform=%@ origin=%@://%@ granted=%@",
                platform.id,
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

typealias AIConversationWebController = JarvisWebPlatformController
