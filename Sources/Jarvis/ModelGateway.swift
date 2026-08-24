import Foundation

struct ModelConfiguration: Codable, Equatable {
    var providerName = "OpenAI Compatible"
    var baseURL = "https://api.openai.com/v1"
    var modelName = "gpt-4o-mini"
}

enum ModelGatewayError: LocalizedError {
    case invalidBaseURL
    case missingResponse
    case noText
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "API Base URL 无效"
        case .missingResponse: "模型没有返回有效内容"
        case .noText: "截图中未识别到可翻译文字"
        case let .server(message): message
        case .invalidResponse: "模型返回格式无法解析"
        }
    }
}

/// The transport layer for model calls.
///
/// Screenshot translation deliberately uses one non-streaming request. The
/// previous implementation opened a stream first and retried with a normal
/// request when a gateway did not support SSE. That made unsupported providers
/// pay for two requests and did not improve the final result because the UI
/// only rendered after receiving the first complete block. Keeping transport
/// separate from the screenshot protocol makes this behavior explicit and
/// prevents provider fallback logic from leaking into the renderer.
final class ModelGateway {
    private static let screenshotTranslationMaxTokens = 1536
    private static let requestTimeout: TimeInterval = 90

    func testConnection(configuration: ModelConfiguration, apiKey: String) async throws {
        _ = try await request(
            prompt: "Reply with exactly: JARVIS_OK",
            image: nil,
            maxTokens: nil,
            configuration: configuration,
            apiKey: apiKey
        )
    }

    func translateScreenshot(
        input: ScreenshotTranslationInput,
        targetLanguage: String,
        configuration: ModelConfiguration,
        apiKey: String
    ) async throws -> ScreenshotTranslationResult {
        let prompt = ScreenshotTranslationProtocol.compactPrompt(
            targetLanguage: targetLanguage,
            imageSize: input.modelPixelSize
        )
        let response = try await request(
            prompt: prompt,
            image: ModelImagePayload(
                data: input.data,
                mediaType: input.mediaType,
                detail: input.detail
            ),
            maxTokens: Self.screenshotTranslationMaxTokens,
            configuration: configuration,
            apiKey: apiKey
        )

        let parseStart = ScreenshotTranslationTiming.now()
        let result = ScreenshotTranslationProtocol.parse(
            response,
            imageSize: input.modelPixelSize
        )
        ScreenshotTranslationLog.logger.debug(
            "vision response parsed durationMs=\(ScreenshotTranslationTiming.milliseconds(since: parseStart), privacy: .public) blockCount=\(result?.blocks.count ?? 0, privacy: .public)"
        )
        guard let result else {
            throw ModelGatewayError.invalidResponse
        }
        guard !result.blocks.isEmpty else {
            throw ModelGatewayError.noText
        }
        return result
    }

    // MARK: - Compatibility surface for tests and prompt inspection

    static func screenshotTranslationPrompt(targetLanguage: String) -> String {
        ScreenshotTranslationProtocol.legacyPrompt(targetLanguage: targetLanguage)
    }

    static func compactScreenshotTranslationPrompt(
        targetLanguage: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> String {
        ScreenshotTranslationProtocol.compactPrompt(
            targetLanguage: targetLanguage,
            imageSize: imageSize
        )
    }

    static func parseCompactScreenshotTranslation(
        _ response: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> ScreenshotTranslationResult? {
        ScreenshotTranslationProtocol.parseCompact(
            response,
            imageSize: imageSize
        )
    }

    static func parseCompactScreenshotTranslationLine(
        _ line: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> ScreenshotTranslationBlock? {
        ScreenshotTranslationProtocol.parseCompactLine(
            line,
            imageSize: imageSize
        )
    }

    static func parseScreenshotTranslation(_ response: String) -> ScreenshotTranslationResult? {
        ScreenshotTranslationProtocol.parseLegacy(response)
    }

    // MARK: - Chat completions transport

    private func request(
        prompt: String,
        image: ModelImagePayload?,
        maxTokens: Int?,
        configuration: ModelConfiguration,
        apiKey: String
    ) async throws -> String {
        let request = try makeRequest(
            prompt: prompt,
            image: image,
            maxTokens: maxTokens,
            configuration: configuration,
            apiKey: apiKey
        )

        let requestStart = ScreenshotTranslationTiming.now()
        let (data, response) = try await URLSession.shared.data(for: request)
        ScreenshotTranslationLog.logger.debug(
            "vision request completed durationMs=\(ScreenshotTranslationTiming.milliseconds(since: requestStart), privacy: .public) responseBytes=\(data.count, privacy: .public) imageBytes=\(image?.data.count ?? 0, privacy: .public) detail=\(image?.detail.rawValue ?? "none", privacy: .public)"
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelGatewayError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "未知错误"
            throw ModelGatewayError.server("API \(httpResponse.statusCode)：\(body.prefix(220))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any]
        else {
            throw ModelGatewayError.invalidResponse
        }

        if let content = Self.textContent(message["content"]), !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw ModelGatewayError.missingResponse
    }

    private func makeRequest(
        prompt: String,
        image: ModelImagePayload?,
        maxTokens: Int?,
        configuration: ModelConfiguration,
        apiKey: String
    ) throws -> URLRequest {
        guard let baseURL = URL(string: configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw ModelGatewayError.invalidBaseURL
        }

        let endpoint: URL = if baseURL.absoluteString.hasSuffix("/chat/completions") {
            baseURL
        } else {
            baseURL.appendingPathComponent("chat/completions")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let messageContent: Any = if let image {
            [
                [
                    "type": "text",
                    "text": prompt
                ],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(image.mediaType);base64,\(image.data.base64EncodedString())",
                        "detail": image.detail.rawValue
                    ]
                ]
            ]
        } else {
            prompt
        }

        var payload: [String: Any] = [
            "model": configuration.modelName,
            "temperature": 0,
            "messages": [[
                "role": "user",
                "content": messageContent
            ]]
        ]
        if let maxTokens {
            payload["max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private static func textContent(_ value: Any?) -> String? {
        if let text = value as? String {
            return text
        }
        if let parts = value as? [[String: Any]] {
            let text = parts.compactMap { part -> String? in
                if let text = part["text"] as? String {
                    return text
                }
                if let text = part["content"] as? String {
                    return text
                }
                return nil
            }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }
}

private struct ModelImagePayload {
    let data: Data
    let mediaType: String
    let detail: ScreenshotTranslationImageDetail
}
