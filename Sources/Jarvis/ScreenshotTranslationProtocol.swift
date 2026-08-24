import Foundation

/// The small, provider-neutral protocol used by screenshot translation.
///
/// Keeping prompt construction and response parsing out of the HTTP gateway
/// makes it possible to change providers without changing coordinate handling
/// or rendering. The compact JSONL response also keeps generation short: the
/// source text is optional and the client only needs the translation plus the
/// original pixel box.
enum ScreenshotTranslationProtocol {
    static func legacyPrompt(targetLanguage: String) -> String {
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

    static func compactPrompt(
        targetLanguage: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> String {
        """
        直接理解截图中的视觉文字并翻译成\(targetLanguage)。不要使用 OCR，不要解释，不要 Markdown，不要输出数组；按视觉阅读顺序逐行输出 JSONL，每行一个 JSON 对象。

        图片尺寸为 \(imageSize.width)×\(imageSize.height) px。唯一允许的格式是：
        {"b":[x,y,width,height],"t":"译文"}

        b 是原文行的像素矩形，原点在左上角，x 向右、y 向下，四个值必须是整数。矩形必须完整覆盖这一行字形并保留少量上下留白，但不能包含相邻行；不要为了译文改变矩形。识别所有清晰可读文字，忽略图标和装饰；不要合并相距明显的区域，也不要遗漏文字。如果没有可翻译文字，输出空内容。
        """
    }

    static func parse(
        _ response: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> ScreenshotTranslationResult? {
        parseCompact(response, imageSize: imageSize) ?? parseLegacy(response)
    }

    static func parseCompact(
        _ response: String,
        imageSize: ScreenshotTranslationImageSize
    ) -> ScreenshotTranslationResult? {
        let blocks = response
            .split(whereSeparator: \.isNewline)
            .compactMap { parseCompactLine(String($0), imageSize: imageSize) }
        guard !blocks.isEmpty else { return nil }
        return ScreenshotTranslationResult(blocks: blocks)
    }

    static func parseCompactLine(
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

    static func parseLegacy(_ response: String) -> ScreenshotTranslationResult? {
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

        let blocks = rawBlocks.compactMap(parseLegacyBlock)
        guard blocks.count == rawBlocks.count else { return nil }
        return ScreenshotTranslationResult(blocks: blocks)
    }

    private static func parseLegacyBlock(_ rawBlock: [String: Any]) -> ScreenshotTranslationBlock? {
        guard let sourceText = rawBlock["source"] as? String,
              let translatedText = rawBlock["translation"] as? String,
              let rawBox = rawBlock["box"] as? [String: Any]
        else {
            return nil
        }

        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              !translation.isEmpty,
              let x = normalizedNumber(rawBox["x"]),
              let y = normalizedNumber(rawBox["y"]),
              let width = normalizedNumber(rawBox["width"]),
              let height = normalizedNumber(rawBox["height"]),
              x >= 0,
              y >= 0,
              width > 0,
              height > 0,
              x + width <= 1,
              y + height <= 1
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
        guard doubleValue.isFinite, doubleValue.rounded() == doubleValue else { return nil }
        return CGFloat(doubleValue)
    }
}
