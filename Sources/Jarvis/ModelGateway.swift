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

final class ModelGateway {
    func testConnection(configuration: ModelConfiguration, apiKey: String) async throws {
        _ = try await request(
            prompt: "Reply with exactly: JARVIS_OK",
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
        let response = try await request(
            prompt: Self.screenshotTranslationPrompt(targetLanguage: targetLanguage),
            imageData: input.data,
            imageDetail: input.detail,
            configuration: configuration,
            apiKey: apiKey
        )
        let parseStart = ScreenshotTranslationTiming.now()
        guard let result = Self.parseScreenshotTranslation(response) else {
            throw ModelGatewayError.invalidResponse
        }
        ScreenshotTranslationLog.logger.debug(
            "vision response parsed durationMs=\(ScreenshotTranslationTiming.milliseconds(since: parseStart), privacy: .public) blockCount=\(result.blocks.count, privacy: .public)"
        )
        guard !result.blocks.isEmpty else {
            throw ModelGatewayError.noText
        }
        return result
    }

    static func screenshotTranslationPrompt(targetLanguage: String) -> String {
        """
        你要直接理解这张截图中的视觉文字，并在一次操作中完成文字识别和翻译。不要依赖本地 OCR，也不要假设截图中只有一种语言。请识别所有清晰可读、应该被翻译的文字，忽略纯装饰图形、图标和无法辨认的内容。

        请严格只返回一个 JSON 对象，不要 Markdown 代码围栏、解释或额外文字，格式如下：
        {
          "blocks": [
            {
              "source": "截图中的完整原文",
              "translation": "翻译成\(targetLanguage)的完整译文",
              "box": { "x": 0.1, "y": 0.2, "width": 0.3, "height": 0.08 }
            }
          ]
        }

        规则：
        1. 按截图中的视觉阅读顺序返回 blocks；同一个文本区域的多行文字放在同一个 block 中，保留原文中的换行。
        2. box 是客户端需要覆盖的原文文本行区域，必须完整包含字形上下缘；单行文字请包含完整行高和少量上下留白，不要只返回紧贴字形的最小像素框。所有数值都必须是 0 到 1 之间的归一化小数。坐标原点在截图左上角，x 向右、y 向下；不要使用像素坐标，也不要使用左下角坐标。
        3. 翻译可能比原文长，但必须原样复用该 block 的 box，不得为了适配译文而改变 x、y、width 或 height。客户端会把译文覆盖绘制在这个原文框内。
        4. 不要合并相距明显的文字区域，不要拆分同一个连续文本区域，不要遗漏可读文字。source 和 translation 都不能为空。
        5. 如果没有可翻译文字，返回 {"blocks": []}。
        """
    }

    static func parseScreenshotTranslation(_ response: String) -> ScreenshotTranslationResult? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }

        let jsonText = String(response[start ... end])
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawBlocks = object["blocks"] as? [[String: Any]]
        else {
            return nil
        }

        let blocks = rawBlocks.compactMap(parseBlock)
        guard blocks.count == rawBlocks.count else { return nil }
        return ScreenshotTranslationResult(blocks: blocks)
    }

    private static func parseBlock(_ rawBlock: [String: Any]) -> ScreenshotTranslationBlock? {
        guard let sourceText = rawBlock["source"] as? String,
              let translatedText = rawBlock["translation"] as? String,
              let rawBox = rawBlock["box"] as? [String: Any]
        else {
            return nil
        }

        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !translation.isEmpty,
              let x = normalizedNumber(rawBox["x"]),
              let y = normalizedNumber(rawBox["y"]),
              let width = normalizedNumber(rawBox["width"]),
              let height = normalizedNumber(rawBox["height"]),
              x >= 0, y >= 0, width > 0, height > 0,
              x + width <= 1, y + height <= 1
        else {
            return nil
        }

        return ScreenshotTranslationBlock(
            sourceText: source,
            translatedText: translation,
            boundingBox: CGRect(x: x, y: y, width: width, height: height)
        )
    }

    private static func normalizedNumber(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite else { return nil }
        return CGFloat(doubleValue)
    }

    private func request(
        prompt: String,
        imageData: Data? = nil,
        imageDetail: ScreenshotTranslationImageDetail = .high,
        configuration: ModelConfiguration,
        apiKey: String
    ) async throws -> String {
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
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messageContent: Any = if let imageData {
            [
                [
                    "type": "text",
                    "text": prompt
                ],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/png;base64,\(imageData.base64EncodedString())",
                        "detail": imageDetail.rawValue
                    ]
                ]
            ]
        } else {
            prompt
        }
        let payload: [String: Any] = [
            "model": configuration.modelName,
            "temperature": 0.2,
            "messages": [[
                "role": "user",
                "content": messageContent
            ]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let requestStart = ScreenshotTranslationTiming.now()
        let (data, response) = try await URLSession.shared.data(for: request)
        ScreenshotTranslationLog.logger.debug(
            "vision request completed durationMs=\(ScreenshotTranslationTiming.milliseconds(since: requestStart), privacy: .public) responseBytes=\(data.count, privacy: .public) detail=\(imageDetail.rawValue, privacy: .public)"
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

        if let content = message["content"] as? String, !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        throw ModelGatewayError.missingResponse
    }
}
