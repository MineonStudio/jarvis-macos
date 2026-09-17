import AppKit
import Foundation

struct ScreenshotTranslationLayoutMetrics: Equatable, Sendable {
    let bounds: CGRect
    let fontSize: CGFloat
    let lineLimit: Int
    let horizontalPadding: CGFloat
    let displayLines: [String]
    let displayLineBounds: [CGRect]
}

private struct ScreenshotTranslationTextUnit {
    let text: String
    let isWhitespace: Bool
}

enum ScreenshotTranslationTextLayout {
    /// 译文最多缩小到基准字号的这个比例。再放不下就按可用行数截断，
    /// 而不是继续缩小——否则同一张图里的字号会相差数倍。
    static let minimumFontScale: CGFloat = 0.6

    static func measuredWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: max(1, fontSize), weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func measuredLineHeight(fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: max(1, fontSize), weight: .medium)
        return font.ascender - font.descender + font.leading
    }

    /// 按整段文本自然折行：中日韩字符可以任意位置断行，拉丁单词、数字、网址整体保留。
    static func wrappedLines(
        _ text: String,
        fontSize: CGFloat,
        maximumWidth: CGFloat
    ) -> [String] {
        let width = max(1, maximumWidth)
        var lines: [String] = []

        for paragraph in text.components(separatedBy: "\n") {
            appendWrappedParagraph(paragraph, fontSize: fontSize, width: width, to: &lines)
        }

        return lines
    }

    static func limitedLines(_ lines: [String], to maximumLines: Int) -> [String] {
        let limit = max(1, maximumLines)
        guard lines.count > limit else { return lines }
        var visible = Array(lines.prefix(limit))
        let last = visible.index(before: visible.endIndex)
        visible[last] = visible[last].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        return visible
    }

    private static func appendWrappedParagraph(
        _ paragraph: String,
        fontSize: CGFloat,
        width: CGFloat,
        to lines: inout [String]
    ) {
        let units = wrappingUnits(in: paragraph)
        guard !units.isEmpty else { return }

        var current = ""
        for unit in units {
            if unit.isWhitespace {
                // 行首不保留空白，行尾空白在入行时去掉。
                if !current.isEmpty {
                    current += unit.text
                }
                continue
            }

            if measuredWidth(current + unit.text, fontSize: fontSize) <= width {
                current += unit.text
                continue
            }
            if !current.isEmpty {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            if measuredWidth(unit.text, fontSize: fontSize) <= width {
                current = unit.text
                continue
            }

            // 单个不可拆单元本身就超宽（长单词、无空格网址）：只能按字符硬拆，
            // 最后一段留给这一行继续拼接。
            let chunks = splitOverwideUnit(unit.text, fontSize: fontSize, width: width)
            lines.append(contentsOf: chunks.dropLast())
            current = chunks.last ?? ""
        }

        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }
    }

    private static func splitOverwideUnit(
        _ unit: String,
        fontSize: CGFloat,
        width: CGFloat
    ) -> [String] {
        var chunks: [String] = []
        var chunk = ""
        for character in unit {
            let candidate = chunk + String(character)
            if chunk.isEmpty || measuredWidth(candidate, fontSize: fontSize) <= width {
                chunk = candidate
            } else {
                chunks.append(chunk)
                chunk = String(character)
            }
        }
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
        return chunks
    }

    private static func wrappingUnits(in text: String) -> [ScreenshotTranslationTextUnit] {
        var units: [ScreenshotTranslationTextUnit] = []
        var word = ""

        for character in text {
            if character.isWhitespace {
                if !word.isEmpty {
                    units.append(ScreenshotTranslationTextUnit(text: word, isWhitespace: false))
                    word = ""
                }
                if let last = units.last, last.isWhitespace {
                    units[units.count - 1] = ScreenshotTranslationTextUnit(
                        text: last.text + String(character),
                        isWhitespace: true
                    )
                } else {
                    units.append(ScreenshotTranslationTextUnit(text: String(character), isWhitespace: true))
                }
                continue
            }

            if breaksEagerly(character) {
                if !word.isEmpty {
                    units.append(ScreenshotTranslationTextUnit(text: word, isWhitespace: false))
                    word = ""
                }
                units.append(ScreenshotTranslationTextUnit(text: String(character), isWhitespace: false))
            } else {
                word.append(character)
            }
        }

        if !word.isEmpty {
            units.append(ScreenshotTranslationTextUnit(text: word, isWhitespace: false))
        }
        return units
    }

    /// 中日韩文字、谚文与全角字符可以在任意位置断行；拉丁词、数字、网址必须整体保留。
    private static func breaksEagerly(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            scalar.properties.isIdeographic
                || (0x2E80 ... 0x2EFF).contains(scalar.value)
                || (0x3000 ... 0x303F).contains(scalar.value)
                || (0x3040 ... 0x30FF).contains(scalar.value)
                || (0xAC00 ... 0xD7AF).contains(scalar.value)
                || (0xFF00 ... 0xFFEF).contains(scalar.value)
        }
    }
}

enum ScreenshotTranslationLayout {
    private static let minimumReadableFontSize: CGFloat = 8
    private static let blockSpacing: CGFloat = 4
    private static let verticalSpacing: CGFloat = 6
    private static let lineShrinkStep: CGFloat = 0.95
    /// 折行时预留的宽度余量，抵消 SwiftUI 与 AppKit 的字宽测量差异。
    private static let widthSafetyMargin: CGFloat = 2

    private struct BlockLimits {
        let maximumWidth: CGFloat
        let maximumHeight: CGFloat
    }

    private struct ResolvedTextLayout {
        let fontSize: CGFloat
        let lines: [String]
    }

    private struct ScreenshotTranslationTextLayoutRequest {
        let text: String
        let baseFontSize: CGFloat
        let minimumFontSize: CGFloat
        let maximumHeight: CGFloat
        let wrappingWidth: CGFloat
        let allowsSingleLineFit: Bool
    }

    static func apply(
        to blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize,
        translationRegion: CGRect? = nil
    ) -> [ScreenshotTranslationRenderBlock] {
        guard !blocks.isEmpty else { return [] }
        let canvasBounds = CGRect(origin: .zero, size: canvasSize)
        let region = clampedBounds(translationRegion ?? canvasBounds, in: canvasBounds)
        let sortedBlocks = blocks.sorted { lhs, rhs in
            if lhs.bounds.minY != rhs.bounds.minY {
                return lhs.bounds.minY < rhs.bounds.minY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        let limits = makeLimits(for: sortedBlocks, in: region)

        return blocks.map { block in
            let metrics = metrics(
                for: block,
                limits: limits[block.id] ?? BlockLimits(
                    maximumWidth: max(1, region.width),
                    maximumHeight: max(1, region.height)
                ),
                region: region
            )
            return ScreenshotTranslationRenderBlock(
                id: block.id,
                sourceText: block.sourceText,
                translatedText: block.translatedText,
                bounds: metrics.bounds,
                confidence: block.confidence,
                sourceLineHeight: block.sourceLineHeight,
                fontSize: metrics.fontSize,
                lineLimit: metrics.lineLimit,
                horizontalPadding: metrics.horizontalPadding,
                sourceLines: block.sourceLines,
                displayLines: metrics.displayLines,
                displayLineBounds: metrics.displayLineBounds
            )
        }
    }

    private static func metrics(
        for block: ScreenshotTranslationRenderBlock,
        limits: BlockLimits,
        region: CGRect
    ) -> ScreenshotTranslationLayoutMetrics {
        let sourceBounds = clampedBounds(block.bounds, in: region)
        let baseFontSize = max(1, resolvedSourceLineHeight(for: block) - 2)
        let horizontalPadding = min(6, max(2, sourceBounds.height * 0.2))
        let availableTextWidth = max(1, limits.maximumWidth - horizontalPadding * 2)
        let wrappingWidth = max(1, availableTextWidth - widthSafetyMargin)
        let minimumFontSize = minimumFontSize(for: baseFontSize)

        let resolved = resolveTextLayout(
            ScreenshotTranslationTextLayoutRequest(
                text: block.translatedText,
                baseFontSize: baseFontSize,
                minimumFontSize: minimumFontSize,
                maximumHeight: limits.maximumHeight,
                wrappingWidth: wrappingWidth,
                allowsSingleLineFit: block.sourceLines.count <= 1
            )
        )

        let capacity = lineCapacity(forFontSize: resolved.fontSize, maximumHeight: limits.maximumHeight)
        let displayLines = resolved.lines.count > capacity
            ? ScreenshotTranslationTextLayout.limitedLines(resolved.lines, to: capacity)
            : resolved.lines
        let displayLineHeight = ScreenshotTranslationTextLayout.measuredLineHeight(
            fontSize: resolved.fontSize
        )
        let requiredHeight = max(
            sourceBounds.height,
            displayLineHeight * CGFloat(displayLines.count) + verticalSpacing * 2
        )
        let height = min(limits.maximumHeight, requiredHeight)
        let contentWidth = displayLines.map {
            ScreenshotTranslationTextLayout.measuredWidth($0, fontSize: resolved.fontSize)
        }.max() ?? 0
        let width = min(
            limits.maximumWidth,
            max(sourceBounds.width, contentWidth + horizontalPadding * 2)
        )
        let finalBounds = CGRect(
            x: sourceBounds.minX,
            y: sourceBounds.minY,
            width: max(sourceBounds.width, width),
            height: max(sourceBounds.height, height)
        )
        let displayLineBounds = makeDisplayLineBounds(
            count: displayLines.count,
            blockBounds: finalBounds,
            lineHeight: displayLineHeight,
            region: region
        )

        return ScreenshotTranslationLayoutMetrics(
            bounds: finalBounds,
            fontSize: resolved.fontSize,
            lineLimit: max(1, displayLines.count),
            horizontalPadding: horizontalPadding,
            displayLines: displayLines,
            displayLineBounds: displayLineBounds
        )
    }

    /// 译文行从块顶部依次向下排；整块盒子仍然覆盖原文区域，只有一行时在框内居中。
    private static func makeDisplayLineBounds(
        count: Int,
        blockBounds: CGRect,
        lineHeight: CGFloat,
        region: CGRect
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        let topInset = count == 1
            ? max(0, min(verticalSpacing, (blockBounds.height - lineHeight) / 2))
            : verticalSpacing
        return (0 ..< count).map { index in
            clampedBounds(
                CGRect(
                    x: blockBounds.minX,
                    y: blockBounds.minY + topInset + CGFloat(index) * lineHeight,
                    width: blockBounds.width,
                    height: max(1, lineHeight)
                ),
                in: region
            )
        }
    }

    private static func makeLimits(
        for blocks: [ScreenshotTranslationRenderBlock],
        in region: CGRect
    ) -> [UUID: BlockLimits] {
        var rows: [[ScreenshotTranslationRenderBlock]] = []
        for block in blocks {
            if let lastRow = rows.indices.last,
               let first = rows[lastRow].first,
               isSameRow(first.bounds, block.bounds)
            {
                rows[lastRow].append(block)
            } else {
                rows.append([block])
            }
        }

        var limits: [UUID: BlockLimits] = [:]
        for rowIndex in rows.indices {
            let row = rows[rowIndex].sorted { $0.bounds.minX < $1.bounds.minX }
            let nextRowTop = rowIndex + 1 < rows.count
                ? rows[rowIndex + 1].map(\.bounds.minY).min() ?? region.maxY
                : region.maxY

            for blockIndex in row.indices {
                let block = row[blockIndex]
                let sourceBounds = clampedBounds(block.bounds, in: region)
                let rightLimit = row.dropFirst(blockIndex + 1).first?.bounds.minX
                    ?? region.maxX
                let maximumWidth = max(
                    sourceBounds.width,
                    min(region.maxX - sourceBounds.minX, rightLimit - sourceBounds.minX - blockSpacing)
                )
                let maximumHeight = max(
                    sourceBounds.height,
                    min(region.maxY - sourceBounds.minY, nextRowTop - sourceBounds.minY - blockSpacing)
                )
                limits[block.id] = BlockLimits(
                    maximumWidth: max(sourceBounds.width, maximumWidth),
                    maximumHeight: max(sourceBounds.height, maximumHeight)
                )
            }
        }
        return limits
    }

    private static func isSameRow(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = max(8, max(lhs.height, rhs.height) * 0.75)
        return abs(lhs.midY - rhs.midY) <= tolerance
    }

    private static func clampedBounds(_ bounds: CGRect, in region: CGRect) -> CGRect {
        let width = min(max(1, bounds.width), max(1, region.width))
        let height = min(max(1, bounds.height), max(1, region.height))
        return CGRect(
            x: min(max(bounds.minX, region.minX), max(region.minX, region.maxX - width)),
            y: min(max(bounds.minY, region.minY), max(region.minY, region.maxY - height)),
            width: width,
            height: height
        )
    }
}

private extension ScreenshotTranslationLayout {
    /// 字号以原文行高为准。Vision 偶尔会给单行文本一个明显偏小的行高
    /// （像素字体、艺术字尤其常见），此时按块高兜底，避免译文被压成极小字号。
    private static func resolvedSourceLineHeight(for block: ScreenshotTranslationRenderBlock) -> CGFloat {
        let blockHeight = max(1, block.bounds.height)
        let measured = block.sourceLineHeight > 0 ? block.sourceLineHeight : blockHeight
        var resolved = min(measured, blockHeight)
        if block.sourceLines.count == 1 {
            resolved = max(resolved, blockHeight * 0.6)
        }
        return max(1, resolved)
    }

    private static func minimumFontSize(for baseFontSize: CGFloat) -> CGFloat {
        let readableFloor = min(minimumReadableFontSize, baseFontSize)
        let scaleFloor = baseFontSize * ScreenshotTranslationTextLayout.minimumFontScale
        return max(1, min(baseFontSize, max(readableFloor, scaleFloor)))
    }

    private static func lineCapacity(forFontSize fontSize: CGFloat, maximumHeight: CGFloat) -> Int {
        let lineHeight = max(1, ScreenshotTranslationTextLayout.measuredLineHeight(fontSize: fontSize))
        return max(1, Int(max(1, maximumHeight - verticalSpacing * 2) / lineHeight))
    }

    private static func resolveTextLayout(
        _ request: ScreenshotTranslationTextLayoutRequest
    ) -> ResolvedTextLayout {
        if request.allowsSingleLineFit {
            let naturalWidth = ScreenshotTranslationTextLayout.measuredWidth(
                request.text,
                fontSize: request.baseFontSize
            )
            if naturalWidth <= request.wrappingWidth {
                return ResolvedTextLayout(fontSize: request.baseFontSize, lines: [request.text])
            }
            // 单行块只有在缩小幅度可接受时才为了保持一行而缩字号，否则自然折行。
            let fittedFontSize = request.baseFontSize * request.wrappingWidth / max(naturalWidth, 1)
            if fittedFontSize >= request.minimumFontSize,
               ScreenshotTranslationTextLayout.measuredWidth(
                   request.text,
                   fontSize: fittedFontSize
               ) <= request.wrappingWidth + 0.5
            {
                return ResolvedTextLayout(fontSize: fittedFontSize, lines: [request.text])
            }
        }

        var fontSize = request.baseFontSize
        var lines = ScreenshotTranslationTextLayout.wrappedLines(
            request.text,
            fontSize: fontSize,
            maximumWidth: request.wrappingWidth
        )
        while lines.count > lineCapacity(forFontSize: fontSize, maximumHeight: request.maximumHeight),
              fontSize > request.minimumFontSize + 0.5
        {
            fontSize = max(request.minimumFontSize, fontSize * lineShrinkStep)
            lines = ScreenshotTranslationTextLayout.wrappedLines(
                request.text,
                fontSize: fontSize,
                maximumWidth: request.wrappingWidth
            )
        }
        return ResolvedTextLayout(fontSize: fontSize, lines: lines)
    }
}
