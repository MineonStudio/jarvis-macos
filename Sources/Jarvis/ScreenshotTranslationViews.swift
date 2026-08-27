import SwiftUI

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
