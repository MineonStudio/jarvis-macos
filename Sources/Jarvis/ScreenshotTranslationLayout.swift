import AppKit
import Foundation

struct ScreenshotTranslationLayoutMetrics: Equatable, Sendable {
    let bounds: CGRect
    let fontSize: CGFloat
    let lineLimit: Int
    let horizontalPadding: CGFloat
}

enum ScreenshotTranslationLayout {
    private static let minimumFontScale: CGFloat = 0.5
    private static let minimumReadableFontSize: CGFloat = 8
    private static let blockSpacing: CGFloat = 4
    private static let verticalSpacing: CGFloat = 6

    private struct LayoutContext {
        let sourceBounds: CGRect
        let baseFontSize: CGFloat
        let horizontalPadding: CGFloat
        let maximumWidth: CGFloat
        let availableTextWidth: CGFloat
        let naturalTextWidth: CGFloat
    }

    static func apply(
        to blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize
    ) -> [ScreenshotTranslationRenderBlock] {
        blocks.map { block in
            let metrics = metrics(for: block, among: blocks, canvasSize: canvasSize)
            return ScreenshotTranslationRenderBlock(
                id: block.id,
                sourceText: block.sourceText,
                translatedText: block.translatedText,
                bounds: metrics.bounds,
                confidence: block.confidence,
                sourceLineHeight: block.sourceLineHeight,
                fontSize: metrics.fontSize,
                lineLimit: metrics.lineLimit,
                horizontalPadding: metrics.horizontalPadding
            )
        }
    }

    static func metrics(
        for block: ScreenshotTranslationRenderBlock,
        among blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize
    ) -> ScreenshotTranslationLayoutMetrics {
        let context = makeContext(
            for: block,
            among: blocks,
            canvasSize: canvasSize
        )
        guard context.naturalTextWidth > context.availableTextWidth else {
            return singleLineMetrics(
                for: block,
                context: context,
                fontSize: context.baseFontSize
            )
        }

        let minimumFontSize = max(
            1,
            min(Self.minimumReadableFontSize, context.baseFontSize * Self.minimumFontScale)
        )
        let fittedFontSize = max(
            minimumFontSize,
            min(
                context.baseFontSize,
                context.baseFontSize * context.availableTextWidth / max(context.naturalTextWidth, 1)
            )
        )
        let fittedTextWidth = measuredWidth(block.translatedText, fontSize: fittedFontSize)
        guard fittedTextWidth > context.availableTextWidth + 1,
              fittedFontSize <= minimumFontSize
        else {
            return singleLineMetrics(
                for: block,
                context: context,
                fontSize: fittedFontSize
            )
        }

        return wrappedMetrics(
            for: block,
            context: context,
            blocks: blocks,
            canvasSize: canvasSize,
            fittedFontSize: fittedFontSize
        )
    }

    private static func makeContext(
        for block: ScreenshotTranslationRenderBlock,
        among blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize
    ) -> LayoutContext {
        let sourceBounds = clampedBounds(block.bounds, in: canvasSize)
        let sourceLineHeight = block.sourceLineHeight > 0
            ? block.sourceLineHeight
            : sourceBounds.height
        let baseFontSize = max(1, sourceLineHeight - 2)
        let horizontalPadding = min(6, max(2, sourceBounds.height * 0.2))
        let maximumWidth = maximumWidth(
            for: block.id,
            at: sourceBounds,
            among: blocks,
            canvasSize: canvasSize
        )
        let availableTextWidth = max(1, maximumWidth - horizontalPadding * 2)
        let naturalTextWidth = measuredWidth(block.translatedText, fontSize: baseFontSize)
        return LayoutContext(
            sourceBounds: sourceBounds,
            baseFontSize: baseFontSize,
            horizontalPadding: horizontalPadding,
            maximumWidth: maximumWidth,
            availableTextWidth: availableTextWidth,
            naturalTextWidth: naturalTextWidth
        )
    }

    private static func singleLineMetrics(
        for block: ScreenshotTranslationRenderBlock,
        context: LayoutContext,
        fontSize: CGFloat
    ) -> ScreenshotTranslationLayoutMetrics {
        let textWidth = measuredWidth(block.translatedText, fontSize: fontSize)
        return ScreenshotTranslationLayoutMetrics(
            bounds: context.sourceBounds.withWidth(
                max(
                    context.sourceBounds.width,
                    min(context.maximumWidth, textWidth + context.horizontalPadding * 2)
                )
            ),
            fontSize: fontSize,
            lineLimit: 1,
            horizontalPadding: context.horizontalPadding
        )
    }

    private static func wrappedMetrics(
        for block: ScreenshotTranslationRenderBlock,
        context: LayoutContext,
        blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize,
        fittedFontSize: CGFloat
    ) -> ScreenshotTranslationLayoutMetrics {
        let lineHeight = measuredLineHeight(fontSize: fittedFontSize)
        let maximumHeight = maximumHeight(
            for: context.sourceBounds,
            among: blocks,
            canvasSize: canvasSize
        )
        let estimatedLineCount = max(2, Int(ceil(
            measuredWidth(block.translatedText, fontSize: fittedFontSize) / context.availableTextWidth
        )))
        let maximumLineCount = max(
            1,
            Int((maximumHeight - verticalSpacing * 2) / max(lineHeight, 1))
        )
        let lineLimit = min(estimatedLineCount, maximumLineCount)
        guard lineLimit > 1 else {
            let requiredFontSize = context.baseFontSize * context.availableTextWidth /
                max(context.naturalTextWidth, 1)
            return singleLineMetrics(
                for: block,
                context: context,
                fontSize: max(1, min(fittedFontSize, requiredFontSize))
            )
        }

        let wrappingFontSize: CGFloat
        if estimatedLineCount > lineLimit {
            let widthForAvailableLines = context.availableTextWidth * CGFloat(lineLimit)
            wrappingFontSize = max(
                1,
                min(
                    fittedFontSize,
                    context.baseFontSize * widthForAvailableLines / max(context.naturalTextWidth, 1)
                )
            )
        } else {
            wrappingFontSize = fittedFontSize
        }
        let wrappingLineHeight = measuredLineHeight(fontSize: wrappingFontSize)
        let height = min(
            maximumHeight,
            max(
                context.sourceBounds.height,
                wrappingLineHeight * CGFloat(lineLimit) + verticalSpacing * 2
            )
        )
        return ScreenshotTranslationLayoutMetrics(
            bounds: CGRect(
                x: context.sourceBounds.minX,
                y: context.sourceBounds.minY,
                width: context.maximumWidth,
                height: height
            ),
            fontSize: wrappingFontSize,
            lineLimit: lineLimit,
            horizontalPadding: context.horizontalPadding
        )
    }

    private static func maximumWidth(
        for blockID: UUID,
        at bounds: CGRect,
        among blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize
    ) -> CGFloat {
        let sameRowBlocks = blocks
            .filter { $0.id != blockID }
            .filter { isSameRow(bounds, $0.bounds) }
            .filter { $0.bounds.minX > bounds.minX }
            .sorted { $0.bounds.minX < $1.bounds.minX }

        let rightLimit = sameRowBlocks.first.map { $0.bounds.minX - blockSpacing } ?? canvasSize.width
        return max(bounds.width, min(canvasSize.width - bounds.minX, rightLimit - bounds.minX))
    }

    private static func maximumHeight(
        for bounds: CGRect,
        among blocks: [ScreenshotTranslationRenderBlock],
        canvasSize: CGSize
    ) -> CGFloat {
        let nextRowTop = blocks
            .filter { !isSameRow(bounds, $0.bounds) }
            .filter { $0.bounds.minY >= bounds.maxY }
            .map(\.bounds.minY)
            .min() ?? canvasSize.height
        return max(bounds.height, min(canvasSize.height - bounds.minY, nextRowTop - bounds.minY - blockSpacing))
    }

    private static func isSameRow(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = max(8, max(lhs.height, rhs.height) * 0.75)
        return abs(lhs.midY - rhs.midY) <= tolerance
    }

    private static func clampedBounds(_ bounds: CGRect, in canvasSize: CGSize) -> CGRect {
        let width = min(max(1, bounds.width), max(1, canvasSize.width))
        let height = min(max(1, bounds.height), max(1, canvasSize.height))
        return CGRect(
            x: min(max(0, bounds.minX), max(0, canvasSize.width - width)),
            y: min(max(0, bounds.minY), max(0, canvasSize.height - height)),
            width: width,
            height: height
        )
    }

    private static func measuredWidth(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static func measuredLineHeight(fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return font.ascender - font.descender + font.leading
    }
}

private extension CGRect {
    func withWidth(_ width: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}
