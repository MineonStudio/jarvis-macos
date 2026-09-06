import SwiftUI

struct ScreenshotTranslationIcon: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "character.bubble.fill" : "character.bubble")
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: 24, height: 24)
            .accessibilityLabel("截图翻译")
    }
}

struct ScreenshotTranslationBlockView: View {
    let block: ScreenshotTranslationRenderBlock

    var body: some View {
        let bounds = block.bounds
        ZStack(alignment: .topLeading) {
            RoundedRectangle(
                cornerRadius: min(8, max(3, bounds.height / 3)),
                style: .continuous
            )
            .fill(.black.opacity(0.72))

            ForEach(Array(zip(displayLines.indices, displayLines)), id: \.0) { index, line in
                let lineBounds = displayLineBounds[index]
                Text(line)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(0)
                    .padding(.horizontal, block.horizontalPadding)
                    .frame(
                        width: max(8, lineBounds.width),
                        height: max(8, lineBounds.height),
                        alignment: .leading
                    )
                    .position(
                        x: lineBounds.midX - bounds.minX,
                        y: lineBounds.midY - bounds.minY
                    )
            }
        }
        .frame(width: max(8, bounds.width), height: max(8, bounds.height))
        .clipped()
        .position(x: bounds.midX, y: bounds.midY)
        .allowsHitTesting(false)
    }

    private var fontSize: CGFloat {
        max(1, block.fontSize > 0 ? block.fontSize : block.bounds.height - 2)
    }

    private var displayLines: [String] {
        block.displayLines.isEmpty ? [block.translatedText] : block.displayLines
    }

    private var displayLineBounds: [CGRect] {
        guard block.displayLineBounds.count >= displayLines.count else {
            let height = max(8, block.bounds.height / CGFloat(displayLines.count))
            return displayLines.indices.map { index in
                CGRect(
                    x: block.bounds.minX,
                    y: block.bounds.minY + CGFloat(index) * height,
                    width: block.bounds.width,
                    height: height
                )
            }
        }
        return Array(block.displayLineBounds.prefix(displayLines.count))
    }
}
