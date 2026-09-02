import Foundation

enum DailyQuoteSource: String, Codable, Equatable, Sendable {
    case builtIn
    case ai
}

struct DailyQuote: Codable, Equatable, Sendable {
    let text: String
    let source: DailyQuoteSource

    private static let builtInQuotes = [
        "把复杂的事情，先做成下一步。",
        "好的工具不替你思考，它让思考更顺畅。",
        "今天不必完成全部，只需让最重要的一步发生。",
        "灵感常常不是等待来的，而是开始之后出现的。",
        "先让想法落地，再让它变得漂亮。"
    ]

    static func builtIn(
        for date: Date = Date(),
        calendar: Calendar = .current
    ) -> Self {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = max(day - 1, 0) % builtInQuotes.count
        return Self(text: builtInQuotes[index], source: .builtIn)
    }

    static func dayKey(
        for date: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct DailyQuoteCache: Codable, Equatable, Sendable {
    let dayKey: String
    let quote: DailyQuote
}

struct DailyQuoteStore {
    static let cacheKey = "jarvis.daily-quote.cache"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for dayKey: String) -> DailyQuote? {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let cache = try? JSONDecoder().decode(DailyQuoteCache.self, from: data),
              cache.dayKey == dayKey
        else {
            return nil
        }
        return cache.quote
    }

    func save(_ quote: DailyQuote, for dayKey: String) {
        guard let data = try? JSONEncoder().encode(DailyQuoteCache(dayKey: dayKey, quote: quote)) else {
            return
        }
        defaults.set(data, forKey: Self.cacheKey)
    }
}

struct DailyQuoteService: Sendable {
    private let apiClient: any AITextCompletionAPI

    init(apiClient: any AITextCompletionAPI = OpenAICompatibleAPIClient()) {
        self.apiClient = apiClient
    }

    func generate(
        for dayKey: String,
        configuration: AIAPIConfiguration
    ) async throws -> DailyQuote {
        let content = try await apiClient.complete(
            systemPrompt: """
            你是 Jarvis 的每日语录生成器。请生成一句简洁、有启发性的中文原创语录。
            不要引用、改写或冒充任何真实人物，不要添加作者署名。
            只返回 JSON，不要返回 Markdown 或额外解释，格式必须是 {\"quote\":\"语录内容\"}。
            """,
            userPrompt: "请为日期 \(dayKey) 生成一句 12 到 40 个汉字的每日语录。",
            configuration: configuration
        )

        guard let data = OpenAICompatibleAPIClient.jsonData(fromModelContent: content) else {
            throw AIAPIError.invalidJSON(context: "每日语录", reason: "返回内容不是有效 JSON")
        }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            let quote = response.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (4 ... 120).contains(quote.count) else {
                throw AIAPIError.invalidSchema(context: "每日语录", reason: "语录长度不符合要求")
            }
            return DailyQuote(text: quote, source: .ai)
        } catch let error as AIAPIError {
            throw error
        } catch {
            throw AIAPIError.decodingError(error, context: "每日语录")
        }
    }
}

private extension DailyQuoteService {
    struct Response: Decodable {
        let quote: String
    }
}
