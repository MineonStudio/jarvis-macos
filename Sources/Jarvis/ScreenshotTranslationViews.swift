import SwiftUI

struct ScreenshotTranslationIcon: View {
    let isSelected: Bool

    var body: some View {
        let accent = isSelected ? Color.accentColor : Color.secondary
        ZStack {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? accent : Color.primary)
                .offset(x: -3, y: 3)

            Image(systemName: "bubble.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(accent)
                .offset(x: 3, y: -3)

            Text("A")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .offset(x: -4, y: 4)

            Text("文")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .offset(x: 4, y: -4)
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("截图翻译")
    }
}

struct ScreenshotTranslationBlockView: View {
    let block: ScreenshotTranslationRenderBlock

    var body: some View {
        let bounds = block.bounds
        Text(block.translatedText)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(maxLineCount)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(.leading)
            .lineSpacing(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(
                width: max(8, bounds.width),
                height: max(8, bounds.height),
                alignment: .leading
            )
            .background(.black.opacity(0.72), in: RoundedRectangle(
                cornerRadius: min(8, max(3, bounds.height / 3)),
                style: .continuous
            ))
            .position(x: bounds.midX, y: bounds.midY)
            .allowsHitTesting(false)
    }

    private var fontSize: CGFloat {
        max(11, min(28, block.bounds.height * 0.62))
    }

    private var maxLineCount: Int {
        max(1, min(4, Int(block.bounds.height / max(fontSize * 1.3, 1))))
    }
}
