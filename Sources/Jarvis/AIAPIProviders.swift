import Foundation

struct AIAPIBaseURL: Hashable, Identifiable, Sendable {
    let title: String
    let url: String

    var id: String {
        url
    }

    init(_ url: String, title: String) {
        self.url = url
        self.title = title
    }
}

enum AIAPIProvider: String, CaseIterable, Hashable, Identifiable, Sendable {
    case openAI = "openai"
    case deepSeek = "deepseek"
    case xAI = "xai"
    case openRouter = "openrouter"
    case moonshot
    case zhipu
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .xAI: "xAI"
        case .openRouter: "OpenRouter"
        case .moonshot: "Kimi"
        case .zhipu: "智谱 AI"
        case .custom: "自定义"
        }
    }

    var brandIconResource: (name: String, fileExtension: String)? {
        switch self {
        case .openAI: ("gpt", "svg")
        case .deepSeek: ("deepseek", "svg")
        case .xAI: ("xai", "png")
        case .openRouter: ("openrouter", "svg")
        case .moonshot: ("kimi", "png")
        case .zhipu: ("zai", "svg")
        case .custom: nil
        }
    }

    var baseURLs: [AIAPIBaseURL] {
        switch self {
        case .openAI:
            [AIAPIBaseURL("https://api.openai.com/v1", title: "官方 API")]
        case .deepSeek:
            [AIAPIBaseURL("https://api.deepseek.com", title: "官方 API")]
        case .xAI:
            [AIAPIBaseURL("https://api.x.ai/v1", title: "官方 API")]
        case .openRouter:
            [AIAPIBaseURL("https://openrouter.ai/api/v1", title: "官方 API")]
        case .moonshot:
            [
                AIAPIBaseURL("https://api.moonshot.cn/v1", title: "中国大陆"),
                AIAPIBaseURL("https://api.moonshot.ai/v1", title: "国际线路")
            ]
        case .zhipu:
            [
                AIAPIBaseURL("https://open.bigmodel.cn/api/paas/v4", title: "中国大陆"),
                AIAPIBaseURL("https://api.z.ai/api/paas/v4", title: "国际线路")
            ]
        case .custom:
            []
        }
    }

    var defaultBaseURL: String {
        baseURLs.first?.url ?? ""
    }

    /// DeepSeek's official OpenAI-compatible endpoint omits the `/v1` prefix.
    /// Other presets use the conventional `/v1/chat/completions` path.
    var chatCompletionsPath: String {
        self == .deepSeek ? "/chat/completions" : "/v1/chat/completions"
    }

    private static let hostMatchers: [(Self, String)] = [
        (.deepSeek, "deepseek"),
        (.openRouter, "openrouter"),
        (.moonshot, "moonshot"),
        (.zhipu, "bigmodel.cn"),
        (.zhipu, "z.ai"),
        (.xAI, "x.ai")
    ]

    static func detect(endpoint: String) -> Self {
        let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() ?? ""
        return hostMatchers.first { hostMatches(host, pattern: $0.1) }?.0
            ?? (hostMatches(host, pattern: "openai") ? .openAI : .custom)
    }

    /// 改进 #5：主机匹配必须认域名边界。以前用 `contains` 子串匹配，
    /// `evil-deepseek.com` 会被误判成 DeepSeek（进而用错请求路径/默认地址）。
    /// 现在只认四种：相等（`x.ai`）、开头（`deepseek.com`）、结尾（`api.moonshot`）、
    /// 中间（`api.deepseek.com`）。
    private static func hostMatches(_ host: String, pattern: String) -> Bool {
        host == pattern
            || host.hasPrefix(pattern + ".")
            || host.hasSuffix("." + pattern)
            || host.contains("." + pattern + ".")
    }
}
