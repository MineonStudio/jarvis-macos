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
        for block in sorted {
            guard let last = merged.last else {
                merged.append(block)
                lastLineBounds.append(block.normalizedBounds)
                continue
            }

            let previousLineBounds = lastLineBounds[merged.count - 1]
            let sameParagraph = isParagraphContinuation(
                block,
                previousLineBounds: previousLineBounds
            )
            if sameParagraph {
                merged[merged.count - 1] = ScreenshotOCRBlock(
                    id: last.id,
                    text: joinedParagraphText(last.text, block.text),
                    normalizedBounds: last.normalizedBounds.union(block.normalizedBounds),
                    confidence: min(last.confidence, block.confidence),
                    lineHeight: previousLineBounds.height
                )
                lastLineBounds[merged.count - 1] = block.normalizedBounds
            } else {
                merged.append(block)
                lastLineBounds.append(block.normalizedBounds)
            }
        }
        return merged
    }

    private static func isParagraphContinuation(
        _ block: ScreenshotOCRBlock,
        previousLineBounds: CGRect
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

        return !startsListItem(block.text)
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
