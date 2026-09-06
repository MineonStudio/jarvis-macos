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

private struct ScreenshotTranslationTextLayoutRequest {
    let text: String
    let sourceLineCount: Int
    let sourceWidths: [CGFloat]
    let baseFontSize: CGFloat
    let minimumFontSize: CGFloat
    let maximumLineCount: Int
    let maximumWidth: CGFloat
}

enum ScreenshotTranslationTextLayout {
    static let minimumFontScale: CGFloat = 0.5

    static func measuredWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: max(1, fontSize), weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func measuredLineHeight(fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: max(1, fontSize), weight: .medium)
        return font.ascender - font.descender + font.leading
    }

    static func wrappedLines(
        _ text: String,
        fontSize: CGFloat,
        maximumWidth: CGFloat
    ) -> [String] {
        let width = max(1, maximumWidth)
        var result: [String] = []

        for paragraph in text.components(separatedBy: "\n") {
            guard !paragraph.isEmpty else {
                result.append("")
                continue
            }

            var current = ""
            for character in paragraph {
                let candidate = current + String(character)
                if current.isEmpty || measuredWidth(candidate, fontSize: fontSize) <= width {
                    current = candidate
                    continue
                }

                if let breakIndex = current.lastIndex(where: { $0.isWhitespace }) {
                    let line = current[..<breakIndex]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        result.append(line)
                    }
                    let remainderStart = current.index(after: breakIndex)
                    current = String(current[remainderStart...]) + String(character)
                } else {
                    result.append(current)
                    current = String(character)
                }
            }
            if !current.isEmpty {
                result.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        return result.isEmpty ? [""] : result
    }

    static func limitedLines(_ lines: [String], to maximumLines: Int) -> [String] {
        let limit = max(1, maximumLines)
        guard lines.count > limit else { return lines }
        var visible = Array(lines.prefix(limit))
        let last = visible.index(before: visible.endIndex)
        visible[last] = visible[last].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        return visible
    }

    static func lineSlots(
        _ text: String,
        sourceWidths: [CGFloat],
        fontSize: CGFloat,
        maximumWidth: CGFloat
    ) -> [String] {
        guard sourceWidths.count > 1 else {
            return wrappedLines(text, fontSize: fontSize, maximumWidth: maximumWidth)
        }

        let characters = Array(text)
        guard !characters.isEmpty else { return [""] }
        var lines: [String] = []
        var cursor = 0

        for slotIndex in sourceWidths.indices {
            guard cursor < characters.count else {
                lines.append("")
                continue
            }
            let slotsRemaining = sourceWidths.count - slotIndex
            let charactersRemaining = characters.count - cursor
            let targetCount = max(1, Int(ceil(
                Double(charactersRemaining) / Double(slotsRemaining)
            )))
            let width = min(maximumWidth, max(1, sourceWidths[slotIndex]))
            var end = min(characters.count, cursor + targetCount)
            while end > cursor + 1,
                  measuredWidth(
                      String(characters[cursor ..< end]),
                      fontSize: fontSize
                  ) > width
            {
                end -= 1
            }

            if end < characters.count {
                let candidate = characters[cursor ..< end]
                if let breakOffset = candidate.lastIndex(where: { $0.isWhitespace }),
                   breakOffset > 0
                {
                    end = breakOffset
                }
            }

            end = max(cursor + 1, end)
            lines.append(
                String(characters[cursor ..< end])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            cursor = end
        }

        if cursor < characters.count {
            lines.append(
                contentsOf: wrappedLines(
                    String(characters[cursor...]),
                    fontSize: fontSize,
                    maximumWidth: maximumWidth
                )
            )
        }
        return lines.isEmpty ? [""] : lines
    }
}

enum ScreenshotTranslationLayout {
    private static let minimumReadableFontSize: CGFloat = 8
    private static let blockSpacing: CGFloat = 4
    private static let verticalSpacing: CGFloat = 6

    private struct BlockLimits {
        let maximumWidth: CGFloat
        let maximumHeight: CGFloat
    }

    private struct ResolvedTextLayout {
        let fontSize: CGFloat
        let lines: [String]
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

    static func metrics(
        for block: ScreenshotTranslationRenderBlock,
        among blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize,
        translationRegion: CGRect? = nil
    ) -> ScreenshotTranslationLayoutMetrics {
        let canvasBounds = CGRect(origin: .zero, size: canvasSize)
        let region = clampedBounds(translationRegion ?? canvasBounds, in: canvasBounds)
        let sortedBlocks = blocks.sorted { lhs, rhs in
            if lhs.bounds.minY != rhs.bounds.minY {
                return lhs.bounds.minY < rhs.bounds.minY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        let limits = makeLimits(for: sortedBlocks, in: region)
        return metrics(
            for: block,
            limits: limits[block.id] ?? BlockLimits(
                maximumWidth: max(1, region.width),
                maximumHeight: max(1, region.height)
            ),
            region: region
        )
    }

    private static func metrics(
        for block: ScreenshotTranslationRenderBlock,
        limits: BlockLimits,
        region: CGRect
    ) -> ScreenshotTranslationLayoutMetrics {
        let sourceBounds = clampedBounds(block.bounds, in: region)
        let sourceLineHeight = block.sourceLineHeight > 0
            ? block.sourceLineHeight
            : sourceBounds.height
        let baseFontSize = max(1, sourceLineHeight - 2)
        let horizontalPadding = min(6, max(2, sourceBounds.height * 0.2))
        let availableTextWidth = max(1, limits.maximumWidth - horizontalPadding * 2)
        let sourceLineCount = max(1, block.sourceLines.count)
        let lineHeight = ScreenshotTranslationTextLayout.measuredLineHeight(
            fontSize: baseFontSize
        )
        let maximumLineCount = max(
            sourceLineCount,
            Int(max(1, (limits.maximumHeight - verticalSpacing * 2) / max(lineHeight, 1)))
        )
        let minimumFontSize = max(
            1,
            min(minimumReadableFontSize, baseFontSize * ScreenshotTranslationTextLayout.minimumFontScale)
        )
        let sourceWidths = block.sourceLines.map(\.bounds.width)

        let textLayout = resolveTextLayout(
            ScreenshotTranslationTextLayoutRequest(
                text: block.translatedText,
                sourceLineCount: sourceLineCount,
                sourceWidths: sourceWidths,
                baseFontSize: baseFontSize,
                minimumFontSize: minimumFontSize,
                maximumLineCount: maximumLineCount,
                maximumWidth: availableTextWidth
            )
        )
        let fontSize = textLayout.fontSize
        let lines = textLayout.lines

        let lineLimit = min(maximumLineCount, max(sourceLineCount, lines.count))
        let displayLines = ScreenshotTranslationTextLayout.limitedLines(lines, to: lineLimit)
        let displayLineHeight = ScreenshotTranslationTextLayout.measuredLineHeight(
            fontSize: fontSize
        )
        let requiredHeight = max(
            sourceBounds.height,
            displayLineHeight * CGFloat(displayLines.count) + verticalSpacing * 2
        )
        let height = min(limits.maximumHeight, requiredHeight)
        let contentWidth = displayLines.map {
            ScreenshotTranslationTextLayout.measuredWidth($0, fontSize: fontSize)
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
            sourceLines: block.sourceLines,
            blockBounds: finalBounds,
            lineHeight: displayLineHeight,
            region: region
        )

        return ScreenshotTranslationLayoutMetrics(
            bounds: finalBounds,
            fontSize: fontSize,
            lineLimit: max(1, lineLimit),
            horizontalPadding: horizontalPadding,
            displayLines: displayLines,
            displayLineBounds: displayLineBounds
        )
    }

    private static func makeDisplayLineBounds(
        count: Int,
        sourceLines: [ScreenshotTranslationLine],
        blockBounds: CGRect,
        lineHeight: CGFloat,
        region: CGRect
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        var result: [CGRect] = sourceLines.prefix(count).map { line in
            clampedBounds(
                CGRect(
                    x: blockBounds.minX,
                    y: line.bounds.minY,
                    width: blockBounds.width,
                    height: max(line.bounds.height, lineHeight)
                ),
                in: region
            )
        }

        while result.count < count {
            let previous = result.last ?? blockBounds
            result.append(
                clampedBounds(
                    CGRect(
                        x: blockBounds.minX,
                        y: previous.maxY,
                        width: blockBounds.width,
                        height: lineHeight
                    ),
                    in: region
                )
            )
        }
        return result
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
    private static func resolveTextLayout(
        _ request: ScreenshotTranslationTextLayoutRequest
    ) -> ResolvedTextLayout {
        var fontSize = request.baseFontSize
        let naturalWidth = ScreenshotTranslationTextLayout.measuredWidth(
            request.text,
            fontSize: request.baseFontSize
        )
        if request.sourceLineCount == 1, naturalWidth > request.maximumWidth {
            let fittedFontSize = max(
                request.minimumFontSize,
                request.baseFontSize * request.maximumWidth / max(naturalWidth, 1)
            )
            if ScreenshotTranslationTextLayout.measuredWidth(
                request.text,
                fontSize: fittedFontSize
            ) <= request.maximumWidth + 1 {
                fontSize = fittedFontSize
            }
        }

        var lines = makeLines(request, fontSize: fontSize, naturalWidth: naturalWidth)
        while lines.count > request.maximumLineCount,
              fontSize > request.minimumFontSize + 0.5
        {
            fontSize = max(request.minimumFontSize, fontSize * 0.9)
            lines = makeLines(request, fontSize: fontSize, naturalWidth: naturalWidth)
        }
        return ResolvedTextLayout(fontSize: fontSize, lines: lines)
    }

    private static func makeLines(
        _ request: ScreenshotTranslationTextLayoutRequest,
        fontSize: CGFloat,
        naturalWidth: CGFloat
    ) -> [String] {
        if request.sourceLineCount > 1 {
            return ScreenshotTranslationTextLayout.lineSlots(
                request.text,
                sourceWidths: request.sourceWidths,
                fontSize: fontSize,
                maximumWidth: request.maximumWidth
            )
        }
        if fontSize == request.baseFontSize, naturalWidth > request.maximumWidth {
            return ScreenshotTranslationTextLayout.wrappedLines(
                request.text,
                fontSize: fontSize,
                maximumWidth: request.maximumWidth
            )
        }
        return [request.text]
    }
}
