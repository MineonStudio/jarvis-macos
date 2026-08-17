import AppKit
import SwiftUI
import WebKit

enum AIConversationProvider: String, CaseIterable, Hashable, Identifiable {
    case deepSeek = "deepseek"
    case gpt
    case doubao

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .gpt: "ChatGPT"
        case .doubao: "豆包"
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
        }
    }
}

@MainActor
final class AIConversationWebController: NSObject, ObservableObject {
    let provider: AIConversationProvider
    let webView: WKWebView

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?

    init(provider: AIConversationProvider) {
        self.provider = provider

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
        VStack(spacing: 0) {
            aiToolbar
            AIConversationBrowserPage(
                controller: currentController
            )
            .id(app.selectedAIProvider)
        }
        .background(Color.jarvisBackground)
    }

    private var aiToolbar: some View {
        HStack {
            providerNavigation

            Spacer(minLength: 0)
            AIConversationBrowserControls(controller: currentController)
        }
        .padding(.horizontal, 28)
        .frame(height: 54)
        .background(Color.jarvisBackground.opacity(0.96))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var providerNavigation: some View {
        HStack(spacing: 2) {
            ForEach(AIConversationProvider.allCases) { provider in
                Button {
                    app.selectedAIProvider = provider
                } label: {
                    Text(provider.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            app.selectedAIProvider == provider ? Color.white : Color.secondary
                        )
                        .frame(
                            minWidth: 72,
                            minHeight: JarvisMetrics.segmentedItemHeight,
                            maxHeight: JarvisMetrics.segmentedItemHeight
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, JarvisMetrics.segmentedItemVerticalPadding)
                        .contentShape(Capsule())
                        .background(
                            app.selectedAIProvider == provider
                                ? Color.accentColor.opacity(0.82)
                                : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .help(provider.title)
            }
        }
        .padding(JarvisMetrics.segmentedControlPadding)
        .jarvisGlass(in: Capsule(), interactive: false)
        .shadow(color: Color.black.opacity(0.10), radius: 14, y: 6)
    }

    private var currentController: AIConversationWebController {
        app.aiConversationController(for: app.selectedAIProvider)
    }
}

private struct AIConversationBrowserControls: View {
    @ObservedObject var controller: AIConversationWebController

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
        .buttonStyle(.plain)
        .foregroundStyle(Color.secondary)
        .opacity(isDisabled ? 0.38 : 1)
        .disabled(isDisabled)
        .jarvisGlass(in: Circle(), interactive: true)
        .help(help)
    }
}

private struct AIConversationBrowserPage: View {
    @ObservedObject var controller: AIConversationWebController

    var body: some View {
        VStack(spacing: 0) {
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
        }
    }
}

private struct AIConversationWebView: NSViewRepresentable {
    @ObservedObject var controller: AIConversationWebController

    func makeNSView(context _: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ _: WKWebView, context _: Context) {}
}
