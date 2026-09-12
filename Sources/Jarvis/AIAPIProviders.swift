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
    case googleGemini = "google-gemini"
    case openRouter = "openrouter"
    case moonshot
    case zhipu
    case dashScope = "dashscope"
    case doubao
    case siliconFlow = "siliconflow"
    case groq
    case mistral
    case xAI = "xai"
    case together
    case fireworks
    case custom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .googleGemini: "Google Gemini"
        case .openRouter: "OpenRouter"
        case .moonshot: "Moonshot / Kimi"
        case .zhipu: "智谱 AI"
        case .dashScope: "阿里云百炼"
        case .siliconFlow: "硅基流动"
        case .groq: "Groq"
        case .mistral: "Mistral"
        case .xAI: "xAI"
        case .together: "Together AI"
        case .fireworks: "Fireworks AI"
        case .doubao: "豆包 / 火山方舟"
        case .custom: "自定义"
        }
    }

    var baseURLs: [AIAPIBaseURL] {
        switch self {
        case .openAI:
            [AIAPIBaseURL("https://api.openai.com/v1", title: "官方 API")]
        case .deepSeek:
            [AIAPIBaseURL("https://api.deepseek.com", title: "官方 API")]
        case .googleGemini:
            [AIAPIBaseURL(
                "https://generativelanguage.googleapis.com/v1beta/openai/",
                title: "OpenAI 兼容接口"
            )]
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
        case .dashScope:
            [
                AIAPIBaseURL(
                    "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    title: "中国（北京）"
                ),
                AIAPIBaseURL(
                    "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
                    title: "新加坡"
                ),
                AIAPIBaseURL(
                    "https://dashscope-us.aliyuncs.com/compatible-mode/v1",
                    title: "美国（弗吉尼亚）"
                )
            ]
        case .siliconFlow:
            [AIAPIBaseURL("https://api.siliconflow.cn/v1", title: "官方 API")]
        case .groq:
            [AIAPIBaseURL("https://api.groq.com/openai/v1", title: "官方 API")]
        case .mistral:
            [AIAPIBaseURL("https://api.mistral.ai/v1", title: "官方 API")]
        case .xAI:
            [AIAPIBaseURL("https://api.x.ai/v1", title: "官方 API")]
        case .together:
            [AIAPIBaseURL("https://api.together.xyz/v1", title: "官方 API")]
        case .fireworks:
            [AIAPIBaseURL("https://api.fireworks.ai/inference/v1", title: "官方 API")]
        case .doubao:
            [AIAPIBaseURL("https://ark.cn-beijing.volces.com/api/v3", title: "中国（北京）")]
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
        (.googleGemini, "generativelanguage.googleapis.com"),
        (.moonshot, "moonshot"),
        (.zhipu, "bigmodel.cn"),
        (.zhipu, "z.ai"),
        (.dashScope, "dashscope"),
        (.dashScope, "maas.aliyuncs.com"),
        (.siliconFlow, "siliconflow"),
        (.groq, "groq"),
        (.mistral, "mistral"),
        (.xAI, "x.ai"),
        (.together, "together"),
        (.fireworks, "fireworks"),
        (.doubao, "volces.com"),
        (.doubao, "volcengine")
    ]

    static func detect(endpoint: String) -> Self {
        let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() ?? ""
        return hostMatchers.first { host.contains($0.1) }?.0
            ?? (host.contains("openai") ? .openAI : .custom)
    }
}
