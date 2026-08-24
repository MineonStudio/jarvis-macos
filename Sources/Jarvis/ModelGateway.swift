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
    case streamUnsupported(String)
    case invalidResponse

    var isStreamUnsupported: Bool {
        if case .streamUnsupported = self {
            return true
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: "API Base URL 无效"
        case .missingResponse: "模型没有返回有效内容"
        case .noText: "截图中未识别到可翻译文字"
        case let .server(message): message
        case let .streamUnsupported(message): message
        case .invalidResponse: "模型返回格式无法解析"
        }
    }
}

final class ModelGateway {
    /// The compact JSONL protocol needs far fewer output tokens than the old
    /// source/translation/normalized-box payload. Keep a ceiling so the model
    /// cannot spend time generating explanations or an oversized report.
    private static let screenshotTranslationMaxTokens = 1536

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
            prompt: Self.compactScreenshotTranslationPrompt(
                targetLanguage: targetLanguage,
                imageSize: input.modelPixelSize
            ),
            imageData: input.data,
            imageDetail: input.detail,
            configuration: configuration,
            apiKey: apiKey,
            maxTokens: Self.screenshotTranslationMaxTokens
        )
        let parseStart = ScreenshotTranslationTiming.now()
        let result = Self.parseCompactScreenshotTranslation(
            response,
            imageSize: input.modelPixelSize
        ) ?? Self.parseScreenshotTranslation(response)
        guard let result else {
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

    func streamScreenshotTranslation(
        input: ScreenshotTranslationInput,
        targetLanguage: String,
        configuration: ModelConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<ScreenshotTranslationBlock, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: ModelGatewayError.invalidResponse)
                    return
                }
                do {
                    try await streamScreenshotTranslation(
                        input: input,
                        targetLanguage: targetLanguage,
                        configuration: configuration,
                        apiKey: apiKey,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
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
        2. box 是客户端需要覆盖的原文文本行区域，必须完整包含字形上下缘；单行文字请包含完整行高和少量上下留白，不要只返回紧贴字形的最小像素框。box 的上、下边缘只能围绕这一行原文，绝不能包含上方或下方相邻行，也不能把译文区域算进去。所有数值都必须是 0 到 1 之间的归一化小数。坐标原点在截图左上角，x 向右、y 向下；不要使用像素坐标，也不要使用左下角坐标。
        3. 翻译可能比原文长，但必须原样复用该 block 的 box，不得为了适配译文而改变 x、y、width 或 height。客户端会把译文覆盖绘制在这个原文框内。
        4. 不要合并相距明显的文字区域，不要拆分同一个连续文本区域，不要遗漏可读文字。source 和 translation 都不能为空。
        5. 如果没有可翻译文字，返回 {"blocks": []}。
        """
    }

    static func compactScreenshotTranslationPrompt(
        targetLanguage: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> String {
        """
        直接理解截图中的视觉文字并翻译成\(targetLanguage)。不要使用 OCR，不要解释，不要 Markdown，不要输出数组；按视觉阅读顺序逐行输出 JSONL，每行一个 JSON 对象。

        图片尺寸为 \(imageSize.width)×\(imageSize.height) px。唯一允许的格式是：
        {"b":[x,y,width,height],"t":"译文"}

        b 是原文行的像素矩形，原点在左上角，x 向右、y 向下，四个值必须是整数。矩形必须完整覆盖这一行字形并保留少量上下留白，但不能包含相邻行；不要为了译文改变矩形。t 不能为空，JSON 字符串中的换行必须写成 \\n。识别所有清晰可读文字，忽略图标和装饰；不要合并相距明显的区域，也不要遗漏文字。如果没有可翻译文字，输出空内容。
        """
    }

    static func parseCompactScreenshotTranslation(
        _ response: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> ScreenshotTranslationResult? {
        let blocks = response
            .split(whereSeparator: \.isNewline)
            .compactMap { parseCompactScreenshotTranslationLine(String($0), imageSize: imageSize) }
        guard !blocks.isEmpty else { return nil }
        return ScreenshotTranslationResult(blocks: blocks)
    }

    static func parseCompactScreenshotTranslationLine(
        _ line: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> ScreenshotTranslationBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = trimmed.hasPrefix("data:")
            ? String(trimmed.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
            : trimmed
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start <= end,
              let data = content[start ... end].data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translatedText = (object["t"] as? String ?? object["translation"] as? String)
        else {
            return nil
        }

        let rawBox: [Any]
        if let compactBox = object["b"] as? [Any] {
            rawBox = compactBox
        } else if let legacyBox = object["box"] as? [String: Any] {
            rawBox = [
                legacyBox["x"] as Any,
                legacyBox["y"] as Any,
                legacyBox["width"] as Any,
                legacyBox["height"] as Any
            ]
        } else {
            return nil
        }
        guard rawBox.count == 4,
              imageSize.width > 0,
              imageSize.height > 0,
              let x = pixelNumber(rawBox[0]),
              let y = pixelNumber(rawBox[1]),
              let width = pixelNumber(rawBox[2]),
              let height = pixelNumber(rawBox[3]),
              x >= 0,
              y >= 0,
              width > 0,
              height > 0,
              x + width <= CGFloat(imageSize.width),
              y + height <= CGFloat(imageSize.height)
        else {
            return nil
        }

        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { return nil }
        let source = (object["s"] as? String ?? object["source"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ScreenshotTranslationBlock(
            sourceText: source,
            translatedText: translation,
            boundingBox: CGRect(
                x: x / CGFloat(imageSize.width),
                y: y / CGFloat(imageSize.height),
                width: width / CGFloat(imageSize.width),
                height: height / CGFloat(imageSize.height)
            )
        )
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

    private static func pixelNumber(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded() == doubleValue else { return nil }
        return CGFloat(doubleValue)
    }

    private func streamScreenshotTranslation(
        input: ScreenshotTranslationInput,
        targetLanguage: String,
        configuration: ModelConfiguration,
        apiKey: String,
        continuation: AsyncThrowingStream<ScreenshotTranslationBlock, Error>.Continuation
    ) async throws {
        let request = try makeRequest(
            prompt: Self.compactScreenshotTranslationPrompt(
                targetLanguage: targetLanguage,
                imageSize: input.modelPixelSize
            ),
            imageData: input.data,
            imageDetail: input.detail,
            configuration: configuration,
            apiKey: apiKey,
            stream: true,
            maxTokens: Self.screenshotTranslationMaxTokens
        )
        let streamStart = ScreenshotTranslationTiming.now()
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelGatewayError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if [400, 404, 405, 422].contains(httpResponse.statusCode) {
                throw ModelGatewayError.streamUnsupported(
                    "API \(httpResponse.statusCode) 不支持截图翻译流式响应"
                )
            }
            throw ModelGatewayError.server("API \(httpResponse.statusCode)：流式翻译请求失败")
        }

        var parser = CompactJSONLParser()
        var responseText = ""
        var blockCount = 0
        for try await line in bytes.lines {
            try Task.checkCancellation()
            let event = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: String
            if event.hasPrefix("data:") {
                payload = String(event.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" {
                    break
                }
            } else {
                // Some OpenAI-compatible gateways ignore stream=true and return
                // one ordinary completion body with HTTP 200.
                payload = event
            }
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = Self.streamContent(from: object),
                  !content.isEmpty
            else {
                continue
            }

            responseText.append(content)
            parser.append(content, imageSize: input.modelPixelSize) { block in
                blockCount += 1
                if blockCount == 1 {
                    ScreenshotTranslationLog.logger.debug(
                        "vision first translation block durationMs=\(ScreenshotTranslationTiming.milliseconds(since: streamStart), privacy: .public)"
                    )
                }
                continuation.yield(block)
            }
        }
        parser.finish(imageSize: input.modelPixelSize) { block in
            blockCount += 1
            continuation.yield(block)
        }
        if blockCount == 0 {
            let parsedResult = Self.parseCompactScreenshotTranslation(
                responseText,
                imageSize: input.modelPixelSize
            ) ?? Self.parseScreenshotTranslation(responseText)
            parsedResult?.blocks.forEach { block in
                blockCount += 1
                continuation.yield(block)
            }
        }
        guard blockCount > 0 else {
            throw ModelGatewayError.noText
        }
        ScreenshotTranslationLog.logger.debug(
            "vision stream completed durationMs=\(ScreenshotTranslationTiming.milliseconds(since: streamStart), privacy: .public) blockCount=\(blockCount, privacy: .public)"
        )
    }

    private static func streamContent(from object: [String: Any]) -> String? {
        guard let choices = object["choices"] as? [[String: Any]],
              let choice = choices.first
        else {
            return nil
        }
        if let delta = choice["delta"] as? [String: Any] {
            return textContent(delta["content"])
        }
        if let message = choice["message"] as? [String: Any] {
            return textContent(message["content"])
        }
        return nil
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

    private func request(
        prompt: String,
        imageData: Data? = nil,
        imageDetail: ScreenshotTranslationImageDetail = .high,
        configuration: ModelConfiguration,
        apiKey: String,
        maxTokens: Int? = nil
    ) async throws -> String {
        let request = try makeRequest(
            prompt: prompt,
            imageData: imageData,
            imageDetail: imageDetail,
            configuration: configuration,
            apiKey: apiKey,
            maxTokens: maxTokens
        )

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

        if let content = Self.textContent(message["content"]), !content.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw ModelGatewayError.missingResponse
    }

    private func makeRequest(
        prompt: String,
        imageData: Data? = nil,
        imageDetail: ScreenshotTranslationImageDetail = .high,
        configuration: ModelConfiguration,
        apiKey: String,
        stream: Bool = false,
        maxTokens: Int? = nil
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
        var payload: [String: Any] = [
            "model": configuration.modelName,
            "temperature": 0,
            "messages": [[
                "role": "user",
                "content": messageContent
            ]]
        ]
        if stream {
            payload["stream"] = true
        }
        if let maxTokens {
            payload["max_tokens"] = maxTokens
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
}

private struct CompactJSONLParser {
    private var buffer = ""

    mutating func append(
        _ fragment: String,
        imageSize: ScreenshotTranslationImageSize,
        emit: (ScreenshotTranslationBlock) -> Void
    ) {
        buffer.append(fragment)
        while let newline = buffer.firstIndex(where: \.isNewline) {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(buffer.startIndex ... newline)
            if let block = ModelGateway.parseCompactScreenshotTranslationLine(line, imageSize: imageSize) {
                emit(block)
            }
        }
    }

    mutating func finish(
        imageSize: ScreenshotTranslationImageSize,
        emit: (ScreenshotTranslationBlock) -> Void
    ) {
        let line = buffer
        buffer.removeAll(keepingCapacity: false)
        if let block = ModelGateway.parseCompactScreenshotTranslationLine(line, imageSize: imageSize) {
            emit(block)
        }
    }
}
