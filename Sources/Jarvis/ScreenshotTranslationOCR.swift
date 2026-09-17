import Foundation

extension ScreenshotTranslationService {
    static func mergedParagraphBlocks(from blocks: [ScreenshotOCRBlock]) -> [ScreenshotOCRBlock] {
        let sorted = blocks.sorted { lhs, rhs in
            let yDelta = lhs.normalizedBounds.minY - rhs.normalizedBounds.minY
            if abs(yDelta) > 0.012 {
                return lhs.normalizedBounds.minY < rhs.normalizedBounds.minY
            }
            return lhs.normalizedBounds.minX < rhs.normalizedBounds.minX
        }

        var merged: [ScreenshotOCRBlock] = []
        var lastLineBounds: [CGRect] = []
        // 每个已合并段落内部观察到的最大行间距，用来把"段内换行"和"段间空行"区分开。
        var largestLineGaps: [CGFloat] = []
        for block in sorted {
            guard let last = merged.last else {
                merged.append(block)
                lastLineBounds.append(block.normalizedBounds)
                largestLineGaps.append(0)
                continue
            }

            let previousLineBounds = lastLineBounds[merged.count - 1]
            let recordedLineGap = largestLineGaps[merged.count - 1]
            let currentBounds = block.normalizedBounds
            let sameParagraph = isParagraphContinuation(
                block,
                previous: last,
                previousLineBounds: previousLineBounds,
                recordedLineGap: recordedLineGap > 0 ? recordedLineGap : nil
            )
            if sameParagraph {
                let mergedBounds = last.normalizedBounds.union(block.normalizedBounds)
                merged[merged.count - 1] = ScreenshotOCRBlock(
                    id: last.id,
                    text: joinedParagraphText(last.text, block.text),
                    normalizedBounds: mergedBounds,
                    confidence: min(last.confidence, block.confidence),
                    lineHeight: last.lineHeight,
                    sourceLines: last.sourceLines + block.sourceLines
                )
                lastLineBounds[merged.count - 1] = block.normalizedBounds
                largestLineGaps[merged.count - 1] = max(
                    recordedLineGap,
                    currentBounds.minY - previousLineBounds.maxY
                )
            } else {
                merged.append(block)
                lastLineBounds.append(block.normalizedBounds)
                largestLineGaps.append(0)
            }
        }
        return merged
    }

    private static func isParagraphContinuation(
        _ block: ScreenshotOCRBlock,
        previous: ScreenshotOCRBlock,
        previousLineBounds: CGRect,
        recordedLineGap: CGFloat?
    ) -> Bool {
        let currentBounds = block.normalizedBounds
        let lineHeight = max(previousLineBounds.height, currentBounds.height)
        let heightRatio = min(previousLineBounds.height, currentBounds.height) /
            max(lineHeight, 0.001)
        let verticalGap = currentBounds.minY - previousLineBounds.maxY
        let verticalLimit = max(0.012, lineHeight * 0.75)
        let horizontalTolerance = max(0.012, lineHeight * 0.9)
        let leftAligned = abs(currentBounds.minX - previousLineBounds.minX) <= horizontalTolerance
        let centered = abs(currentBounds.midX - previousLineBounds.midX) <= horizontalTolerance * 2

        guard heightRatio >= 0.65,
              verticalGap >= -lineHeight * 0.25,
              verticalGap <= verticalLimit,
              leftAligned || centered
        else {
            return false
        }

        // 段内行距是稳定的：如果这一行和前一行之间的间距明显大于
        // 段落内部已经观察到的行距，那就是段间空行，不能并成一段。
        if let recordedLineGap {
            let calibratedLimit = max(0.004, recordedLineGap * 1.5)
            guard verticalGap <= calibratedLimit else { return false }
        }

        guard !startsListItem(block.text),
              !startsListItem(previous.text)
        else {
            return false
        }

        return !isLikelyStandaloneRow(block, previous: previous)
    }

    private static func isLikelyStandaloneRow(
        _ block: ScreenshotOCRBlock,
        previous: ScreenshotOCRBlock
    ) -> Bool {
        let currentText = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousText = previous.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortText = currentText.count <= 32 && previousText.count <= 32
        let compactWidth = max(
            block.normalizedBounds.width,
            previous.normalizedBounds.width
        ) <= 0.55
        let aligned = abs(block.normalizedBounds.minX - previous.normalizedBounds.minX) <= 0.04
        let similarWidth = abs(
            block.normalizedBounds.width - previous.normalizedBounds.width
        ) <= 0.12
        return shortText && compactWidth && aligned && similarWidth
    }

    private static func startsListItem(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }
        if "•·▪◦‣⁃-–—".contains(first) {
            return true
        }

        guard first.isNumber else { return false }
        let marker = trimmed.drop { $0.isNumber }.drop { $0.isWhitespace }
        return marker.first == "." || marker.first == ")" || marker.first == "、"
    }

    private static func joinedParagraphText(_ left: String, _ right: String) -> String {
        if left.last == "\u{00AD}" {
            return "\(left.dropLast())\(right)"
        }
        if left.last == "-", right.first?.isLetter == true {
            return "\(left.dropLast())\(right)"
        }
        let needsSpace = left.last?.isASCII == true || right.first?.isASCII == true
        return needsSpace ? "\(left) \(right)" : left + right
    }
}
