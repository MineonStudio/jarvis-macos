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

enum AIAPIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidEndpoint
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "请先在设置中配置 AI 翻译服务"
        case .invalidEndpoint:
            "AI 翻译服务地址无效"
        case .invalidResponse:
            "AI 翻译服务返回了无法解析的结果"
        case let .server(message):
            message
        }
    }
}

struct OpenAICompatibleAPIClient: AITranslationAPI, Sendable {
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
            throw AIAPIError.invalidResponse
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
            throw AIAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = Self.serverMessage(from: data)
                ?? "AI 翻译服务请求失败（\(httpResponse.statusCode)）"
            throw AIAPIError.server(message)
        }

        guard let content = Self.chatCompletionContent(from: data),
              let responseData = Self.jsonDataFromModelContent(content),
              let result = try? JSONDecoder().decode(TranslationResponse.self, from: responseData)
        else {
            throw AIAPIError.invalidResponse
        }
        return result.translations
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

    private static func chatCompletionContent(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else {
            return nil
        }
        if let content = message["content"] as? String {
            return content
        }
        if let contentParts = message["content"] as? [[String: Any]] {
            return contentParts.compactMap { $0["text"] as? String }.joined()
        }
        return nil
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
