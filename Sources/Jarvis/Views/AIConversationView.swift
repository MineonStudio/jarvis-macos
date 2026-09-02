import AppKit
import SwiftUI

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

    var webPlatform: JarvisWebPlatformDescriptor {
        JarvisWebPlatformDescriptor(
            id: "ai.\(rawValue)",
            title: title,
            url: url,
            allowedHosts: allowedHosts
        )
    }

    func allowsHost(_ host: String) -> Bool {
        JarvisWebHostAllowlist.contains(host, in: allowedHosts)
    }
}

struct AIConversationView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showsDownloadManager = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: JarvisToolbarMetrics.controlSpacing) {
                        JarvisToolbarGroupedPicker(
                            items: AIConversationProvider.allCases,
                            selection: selectedProvider,
                            title: { $0.title },
                            icon: { provider, isSelected in
                                AIConversationProviderIcon(provider: provider, isSelected: isSelected)
                            }
                        )
                        JarvisWebPlatformBrowserControls(controller: currentController)
                    }
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    JarvisWebPlatformDownloadButton(
                        controller: currentController,
                        showsDownloadManager: $showsDownloadManager,
                        emptyHint: "在第三方AI平台页面点击文件下载后，任务会显示在这里"
                    )
                }
            },
            content: {
                JarvisWebPlatformBrowserPage(controller: currentController)
                    .id(app.selectedAIProvider)
            }
        )
    }

    private var selectedProvider: Binding<AIConversationProvider> {
        Binding(
            get: { app.selectedAIProvider },
            set: { app.selectAIProvider($0) }
        )
    }

    private var currentController: JarvisWebPlatformController {
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
        .frame(width: 16, height: 16)
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
