import Foundation
import Security

struct AIAPIConfiguration: Equatable, Sendable {
    static let apiEndpointKey = "jarvis.ai.api.endpoint"
    static let apiModelKey = "jarvis.ai.api.model"
    static let apiNameKey = "jarvis.ai.api.name"
    static let apiModelsKey = "jarvis.ai.api.models"
    static let endpointKey = "jarvis.ai.endpoint"
    static let modelKey = "jarvis.ai.model"
    static let providerEndpointKey = "jarvis.ai.provider.endpoint"
    static let paidEndpointKey = "jarvis.ai.paid-endpoint"
    static let paidModelKey = "jarvis.ai.paid-model"
    static let paidModelsKey = "jarvis.ai.paid-models"
    static let legacyEndpointKey = "jarvis.screenshot.translation.endpoint"
    static let legacyModelKey = "jarvis.screenshot.translation.model"
    static let defaultEndpoint = "https://api.openai.com/v1/chat/completions"
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    var endpoint: String
    var model: String
    var apiKey: String
    var name: String = ""

    var isKeyless: Bool {
        Self.isKeylessEndpoint(endpoint)
    }

    var isConfigured: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (isKeyless || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    static func isKeylessEndpoint(_ rawValue: String) -> Bool {
        let host = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))?.host?
            .lowercased() ?? ""
        return host == "opencode.ai" || host.hasSuffix(".opencode.ai")
    }

    static func load(
        defaults: UserDefaults = .standard,
        keychain: AIAPIKeychain = .shared
    ) -> Self {
        load(defaults: defaults, resolvedAPIKey: keychain.readIfAvailable())
    }

    static func loadProvider(
        defaults: UserDefaults = .standard,
        keychain: AIAPIKeychain = .shared
    ) -> Self {
        load(defaults: defaults, keychain: keychain)
    }

    static func load(
        defaults: UserDefaults = .standard,
        resolvedAPIKey: String?
    ) -> Self {
        let endpoint = nonKeyless(defaults.string(forKey: apiEndpointKey))
            ?? nonKeyless(defaults.string(forKey: providerEndpointKey))
            ?? nonKeyless(defaults.string(forKey: paidEndpointKey))
            ?? nonKeyless(defaults.string(forKey: endpointKey))
            ?? nonKeyless(defaults.string(forKey: legacyEndpointKey))
            ?? defaultEndpoint
        let model = nonFreeModel(defaults.string(forKey: apiModelKey))
            ?? nonFreeModel(defaults.string(forKey: paidModelKey))
            ?? nonFreeModel(defaults.string(forKey: modelKey))
            ?? nonFreeModel(defaults.string(forKey: legacyModelKey))
            ?? defaultModel
        let storedName = defaults.string(forKey: apiNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Self(
            endpoint: endpoint,
            model: model,
            apiKey: resolvedAPIKey ?? "",
            name: storedName.isEmpty
                ? AIModelOption.providerTitle(for: endpoint, isFree: false)
                : storedName
        )
    }

    static func loadProvider(
        defaults: UserDefaults = .standard,
        resolvedAPIKey: String?
    ) -> Self {
        load(defaults: defaults, resolvedAPIKey: resolvedAPIKey)
    }

    static func migrateLegacyKeys(defaults: UserDefaults = .standard) {
        if defaults.string(forKey: apiEndpointKey) == nil,
           let endpoint = nonKeyless(
               defaults.string(forKey: providerEndpointKey)
                   ?? defaults.string(forKey: paidEndpointKey)
                   ?? defaults.string(forKey: endpointKey)
                   ?? defaults.string(forKey: legacyEndpointKey)
           )
        {
            defaults.set(endpoint, forKey: apiEndpointKey)
        }
        if defaults.string(forKey: apiModelKey) == nil,
           let model = nonFreeModel(
               defaults.string(forKey: paidModelKey)
                   ?? defaults.string(forKey: modelKey)
                   ?? defaults.string(forKey: legacyModelKey)
           )
        {
            defaults.set(model, forKey: apiModelKey)
        }
        if defaults.string(forKey: apiModelsKey) == nil,
           let models = defaults.stringArray(forKey: paidModelsKey),
           !models.isEmpty
        {
            defaults.set(models, forKey: apiModelsKey)
        }
        if defaults.string(forKey: apiNameKey) == nil {
            let endpoint = defaults.string(forKey: apiEndpointKey)
                ?? defaults.string(forKey: providerEndpointKey)
                ?? ""
            let inferred = AIModelOption.providerTitle(for: endpoint, isFree: false)
            if inferred != "已配置" {
                defaults.set(inferred, forKey: apiNameKey)
            }
        }
    }

    static func hasStoredAPIEndpoint(defaults: UserDefaults = .standard) -> Bool {
        nonKeyless(defaults.string(forKey: apiEndpointKey)) != nil
            || nonKeyless(defaults.string(forKey: providerEndpointKey)) != nil
    }

    static func nonKeyless(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isKeylessEndpoint(rawValue)
        else {
            return nil
        }
        return rawValue
    }

    static func nonFreeModel(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !HermesFreeModelCatalog.isAnonymousFreeModel(trimmed) else {
            return nil
        }
        return trimmed
    }

    var openAIBaseURL: String {
        let trimmed = endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let stripped = if trimmed.lowercased().hasSuffix("/chat/completions") {
            String(trimmed.dropLast("/chat/completions".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            trimmed
        }
        guard let components = URLComponents(string: stripped) else {
            return stripped
        }
        let path = components.path
        if path.isEmpty || path == "/" {
            return stripped + "/v1"
        }
        return stripped
    }
}

protocol AITextCompletionAPI: Sendable {
    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String
}

protocol AIAPIConnectionTesting: Sendable {
    func testConnection(configuration: AIAPIConfiguration) async throws
}

enum AIAPIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidEndpoint
    case invalidTransportResponse
    case invalidCompletionEnvelope(String)
    case invalidJSON(context: String, reason: String)
    case invalidSchema(context: String, reason: String)
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

struct OpenAICompatibleAPIClient: AITextCompletionAPI, AIAPIConnectionTesting, Sendable {
    func testConnection(configuration: AIAPIConfiguration) async throws {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedEndpointURL(from: configuration.endpoint) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAuthentication(to: &request, configuration: configuration)
        // json_object mode rejects prompts that do not contain the word "json".
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "user", "content": "Reply with JSON: {\"ok\":true}"]
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

        try Self.validateConnectionEnvelope(from: data)
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        configuration: AIAPIConfiguration
    ) async throws -> String {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedEndpointURL(from: configuration.endpoint) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.applyAuthentication(to: &request, configuration: configuration)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model,
            "temperature": 0.7,
            "max_tokens": 2048,
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

    func listModels(configuration: AIAPIConfiguration) async throws -> [String] {
        guard configuration.isConfigured else { throw AIAPIError.missingConfiguration }
        guard let endpoint = Self.normalizedModelsURL(from: configuration.endpoint) else {
            throw AIAPIError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        Self.applyAuthentication(to: &request, configuration: configuration)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIAPIError.invalidTransportResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = Self.serverMessage(from: data)
                ?? "AI 服务请求失败（\(httpResponse.statusCode)）"
            throw AIAPIError.server(message)
        }
        return try Self.modelIdentifiers(from: data)
    }

    static func applyAuthentication(
        to request: inout URLRequest,
        configuration: AIAPIConfiguration
    ) {
        if configuration.isKeyless {
            request.setValue("https://hermes-agent.nousresearch.com", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Jarvis", forHTTPHeaderField: "X-Title")
            return
        }
        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    static func normalizedEndpointURL(from rawValue: String) -> URL? {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty
        else {
            return nil
        }
        let path = components.path
        if path.hasSuffix("/chat/completions") {
            return components.url
        }
        if path.isEmpty || path == "/" || path == "/v1" {
            components.path = "/v1/chat/completions"
        } else {
            components.path = path.hasSuffix("/")
                ? path + "chat/completions"
                : path + "/chat/completions"
        }
        return components.url
    }

    static func normalizedModelsURL(from rawValue: String) -> URL? {
        guard let chatURL = normalizedEndpointURL(from: rawValue),
              var components = URLComponents(url: chatURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        let path = components.path
        if path.hasSuffix("/chat/completions") {
            components.path = String(path.dropLast("/chat/completions".count)) + "/models"
        } else {
            components.path = path.hasSuffix("/") ? path + "models" : path + "/models"
        }
        return components.url
    }

    static func modelIdentifiers(from data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAPIError.invalidCompletionEnvelope("模型列表不是 JSON 对象")
        }
        guard let items = root["data"] as? [[String: Any]] else {
            throw AIAPIError.invalidCompletionEnvelope("缺少 data 数组")
        }
        let identifiers = items.compactMap { item -> String? in
            let identifier = (item["id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return identifier.isEmpty ? nil : identifier
        }
        guard !identifiers.isEmpty else {
            throw AIAPIError.invalidCompletionEnvelope("模型列表为空")
        }
        return identifiers
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
        if let finishReason = choices[0]["finish_reason"] as? String,
           finishReason == "length"
        {
            throw AIAPIError.invalidCompletionEnvelope("生成结果被截断，请减少输入或更换模型")
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

    static func validateConnectionEnvelope(from data: Data) throws {
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
            return
        }
        if let contentParts = message["content"] as? [[String: Any]] {
            let content = contentParts.compactMap { $0["text"] as? String }.joined()
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AIAPIError.invalidCompletionEnvelope("choices[0].message.content 文本片段为空")
            }
            return
        }
        throw AIAPIError.invalidCompletionEnvelope("缺少 choices[0].message.content，或 content 类型不受支持")
    }

    static func jsonData(fromModelContent content: String) -> Data? {
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
        guard let data = unfenced.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else {
            return nil
        }
        return data
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

final class AIAPIKeychain: @unchecked Sendable {
    static let shared = AIAPIKeychain()

    private let service = "\(JarvisAppIdentity.bundleIdentifier).ai"
    private let legacyService = "\(JarvisAppIdentity.bundleIdentifier).screenshot-translation"
    private let account = "api-key"

    func readIfAvailable() -> String {
        (try? read()) ?? ""
    }

    func read() throws -> String? {
        if let value = try read(service: service) {
            return value
        }
        guard let legacy = try read(service: legacyService) else {
            return nil
        }
        try? write(legacy)
        return legacy
    }

    private func read(service: String) throws -> String? {
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
        try delete()
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess else { throw KeychainError(status: insertStatus) }
    }

    func delete() throws {
        try delete(service: service)
        try delete(service: legacyService)
    }

    private func delete(service: String) throws {
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
