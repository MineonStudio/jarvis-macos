import SwiftUI

struct ScreenshotTranslationIcon: View {
    let isSelected: Bool
    /// 选中态的图标颜色。工具栏把它压在 accent 胶囊上，得用白色——胶囊和图标
    /// 都是 accent 的话整个糊在一起。
    var selectedColor: Color = .accentColor

    var body: some View {
        Image(systemName: isSelected ? "character.bubble.fill" : "character.bubble")
            .font(
                .system(
                    size: ScreenshotToolbarIconMetrics.pointSize(for: "character.bubble"),
                    weight: .medium
                )
            )
            .foregroundStyle(isSelected ? selectedColor : Color.secondary)
            .frame(
                width: ScreenshotToolbarIconMetrics.box,
                height: ScreenshotToolbarIconMetrics.box
            )
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
