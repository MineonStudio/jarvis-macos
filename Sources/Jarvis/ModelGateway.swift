import Foundation

struct ModelConfiguration: Codable, Equatable {
    var providerName = "OpenAI Compatible"
    var baseURL = "https://api.openai.com/v1"
    var modelName = "gpt-4o-mini"
}

enum ModelGatewayError: LocalizedError {
    case invalidBaseURL
    case missingResponse
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "API Base URL 无效"
        case .missingResponse: return "模型没有返回有效内容"
        case .server(let message): return message
        case .invalidResponse: return "模型返回格式无法解析"
        }
    }
}

final class ModelGateway {
    func testConnection(configuration: ModelConfiguration, apiKey: String) async throws {
        _ = try await request(
            prompt: "Reply with exactly: JARVIS_OK",
            configuration: configuration,
            apiKey: apiKey
        )
    }

    func translateText(
        _ sourceText: String,
        targetLanguage: String,
        configuration: ModelConfiguration,
        apiKey: String
    ) async throws -> String {
        try await request(
            prompt: Self.translationPrompt(sourceText: sourceText, targetLanguage: targetLanguage),
            configuration: configuration,
            apiKey: apiKey
        )
    }

    static func translationPrompt(targetLanguage: String) -> String {
        translationPrompt(sourceText: "", targetLanguage: targetLanguage)
    }

    static func translationPrompt(sourceText: String, targetLanguage: String) -> String {
        "下面是由 macOS 本地 OCR 识别出的原文。请自动判断源语言，并将原文翻译成\(targetLanguage)。保留原文的段落、列表和换行结构，只返回完整译文，不要解释过程。若原文为空，只返回：未识别到文字。\n\n原文：\n---\n\(sourceText)\n---"
    }

    private func request(
        prompt: String,
        configuration: ModelConfiguration,
        apiKey: String
    ) async throws -> String {
        guard let baseURL = URL(string: configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw ModelGatewayError.invalidBaseURL
        }

        let endpoint: URL
        if baseURL.absoluteString.hasSuffix("/chat/completions") {
            endpoint = baseURL
        } else {
            endpoint = baseURL.appendingPathComponent("chat/completions")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": configuration.modelName,
            "temperature": 0.2,
            "messages": [[
                "role": "user",
                "content": prompt
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelGatewayError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "未知错误"
            throw ModelGatewayError.server("API \(httpResponse.statusCode)：\(body.prefix(220))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw ModelGatewayError.invalidResponse
        }

        if let content = message["content"] as? String, !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        throw ModelGatewayError.missingResponse
    }
}
