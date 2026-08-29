import Foundation
import Security

struct AIAPIConfiguration: Equatable, Sendable {
    static let endpointKey = "jarvis.screenshot.translation.endpoint"
    static let modelKey = "jarvis.screenshot.translation.model"
    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
    static let defaultModel = "gpt-4o-mini"

    var endpoint: String
    var model: String
    var apiKey: String

    var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func load(
        defaults: UserDefaults = .standard,
        keychain: AIAPIKeychain = .shared
    ) -> Self {
        Self(
            endpoint: defaults.string(forKey: endpointKey) ?? defaultEndpoint,
            model: defaults.string(forKey: modelKey) ?? defaultModel,
            apiKey: (try? keychain.read()) ?? ""
        )
    }
}

struct AITranslationInput: Codable, Equatable, Sendable {
    let id: String
    let text: String
}

struct AITranslationOutput: Codable, Equatable, Sendable {
    let id: String
    let translation: String
}

protocol AITranslationAPI: Sendable {
    func translate(
        _ items: [AITranslationInput],
        targetLanguage: String,
        configuration: AIAPIConfiguration
    ) async throws -> [AITranslationOutput]
}

protocol AITextCompletionAPI: Sendable {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String
}

enum AIAPIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidEndpoint
    case invalidTransportResponse
    case invalidCompletionEnvelope(String)
    case invalidJSON(context: String, reason: String)
    case invalidSchema(context: String, reason: String)
    case incompleteTranslation(expected: Int, actual: Int)
    case emptyGeneratedContent(context: String)
    case duplicateGeneratedContent(context: String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "请先在设置中配置 AI 服务"
        case .invalidEndpoint:
            "AI 服务地址无效"
        case .invalidTransportResponse:
            "AI 服务响应异常：未收到有效的 HTTP 响应"
        case let .invalidCompletionEnvelope(reason):
            "AI 服务响应格式错误：\(reason)"
        case let .invalidJSON(context, reason):
            "\(context)结果不是有效 JSON：\(reason)"
        case let .invalidSchema(context, reason):
            "\(context)字段结构不符合要求：\(reason)"
        case let .incompleteTranslation(expected, actual):
            "AI 翻译结果不完整：应返回 \(expected) 条，实际 \(actual) 条"
        case let .emptyGeneratedContent(context):
            "\(context)没有生成有效内容"
        case let .duplicateGeneratedContent(context):
            "\(context)没有生成新的内容，请稍后再试"
        case let .server(message):
            message
        }
    }

    static func decodingError(_ error: Error, context: String) -> Self {
        guard let decodingError = error as? DecodingError else {
            return .invalidJSON(context: context, reason: error.localizedDescription)
        }

        switch decodingError {
        case let .dataCorrupted(decodingContext):
            return .invalidJSON(
                context: context,
                reason: "\(codingPathDescription(decodingContext.codingPath))：\(decodingContext.debugDescription)"
            )
        case let .keyNotFound(key, decodingContext):
            return .invalidSchema(
                context: context,
                reason: "缺少字段 \(codingPathDescription(decodingContext.codingPath, appending: key))"
            )
        case let .typeMismatch(type, decodingContext):
            return .invalidSchema(
                context: context,
                reason: "字段 \(codingPathDescription(decodingContext.codingPath)) 应为 \(String(describing: type))"
            )
        case let .valueNotFound(type, decodingContext):
            return .invalidSchema(
                context: context,
                reason: "字段 \(codingPathDescription(decodingContext.codingPath)) 为空，期望 \(String(describing: type))"
            )
        @unknown default:
            return .invalidSchema(context: context, reason: "字段结构无法识别")
        }
    }

    private static func codingPathDescription(
        _ codingPath: [any CodingKey],
        appending key: (any CodingKey)? = nil
    ) -> String {
        let keys = codingPath.map(\.stringValue) + (key.map { [$0.stringValue] } ?? [])
        return keys.isEmpty ? "根对象" : keys.joined(separator: ".")
    }
}

struct OpenAICompatibleAPIClient: AITranslationAPI, AITextCompletionAPI, Sendable {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = endpointURL(from: configuration.endpoint) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "temperature": 0.7,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAPIError.invalidTransportResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = Self.serverMessage(from: data)
                ?? "AI 服务请求失败（\(httpResponse.statusCode)）"
            throw AIAPIError.server(message)
        }
        return try Self.chatCompletionContent(from: data)
    }

    func translate(
        _ items: [AITranslationInput],
        targetLanguage: String,
        configuration: AIAPIConfiguration
    ) async throws -> [AITranslationOutput] {
        guard !items.isEmpty else { return [] }
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = endpointURL(from: configuration.endpoint) else {
            throw AIAPIError.invalidEndpoint
        }

        let sourceData = try JSONEncoder().encode(items)
        guard let sourceText = String(data: sourceData, encoding: .utf8) else {
            throw AIAPIError.invalidJSON(context: "翻译", reason: "请求内容无法转换为 UTF-8")
        }
        let systemPrompt = """
        Translate each item into \(targetLanguage). Preserve meaning, numbers, code, URLs, punctuation, and line breaks.
        Return JSON only: {"translations":[{"id":"original-id","translation":"translated text"}]}. Include every item exactly once.
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": sourceText]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAPIError.invalidTransportResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = Self.serverMessage(from: data)
                ?? "AI 翻译服务请求失败（\(httpResponse.statusCode)）"
            throw AIAPIError.server(message)
        }

        let content = try Self.chatCompletionContent(from: data)
        guard let responseData = Self.jsonDataFromModelContent(content) else {
            throw AIAPIError.invalidJSON(context: "翻译", reason: "返回内容无法转换为 UTF-8")
        }
        do {
            return try JSONDecoder().decode(TranslationResponse.self, from: responseData).translations
        } catch {
            throw AIAPIError.decodingError(error, context: "翻译")
        }
    }

    private func endpointURL(from rawValue: String) -> URL? {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed),
              components.scheme != nil,
              components.host != nil
        else {
            return nil
        }
        if !components.path.hasSuffix("/chat/completions") {
            components.path = components.path.hasSuffix("/")
                ? components.path + "chat/completions"
                : components.path + "/chat/completions"
        }
        return components.url
    }

    private static func chatCompletionContent(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("响应正文不是 JSON 对象")
        }
        guard let choices = root["choices"] as? [[String: Any]], !choices.isEmpty else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 choices 数组或 choices 为空")
        }
        guard let message = choices[0]["message"] as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message")
        }
        if let content = message["content"] as? String {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 为空")
            }
            return content
        }
        if let contentParts = message["content"] as? [[String: Any]] {
            let content = contentParts.compactMap { $0["text"] as? String }.joined()
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 文本片段为空")
            }
            return content
        }
        throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message.content，或 content 类型不受支持")
    }

    private static func jsonDataFromModelContent(_ content: String) -> Data? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil
        {
            return data
        }
        let unfenced = trimmed
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return unfenced.data(using: .utf8)
    }

    private static func serverMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any],
              let message = error["message"] as? String
        else {
            return nil
        }
        return message
    }
}

private extension OpenAICompatibleAPIClient {
    struct TranslationResponse: Decodable {
        let translations: [AITranslationOutput]
    }
}

final class AIAPIKeychain: @unchecked Sendable {
    static let shared = AIAPIKeychain()

    private let service = "\(JarvisAppIdentity.bundleIdentifier).screenshot-translation"
    private let account = "api-key"

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            throw KeychainError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else { throw KeychainError(status: insertStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Keychain 操作失败（\(status)）"
    }
}
