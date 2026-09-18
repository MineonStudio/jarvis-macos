import AppKit
import CoreGraphics

/// 标注文字的排版与绘制：画布预览、内联输入控件、导出管线共用同一套几何。
///
/// 同一段文字有三个渲染端，各写各的排版就会各偏各的：预览（原来的 SwiftUI `Text`）
/// 与导出在大字号下能差出半个字高，而输入控件（`NSTextView`）又是第三个位置——
/// 于是「点一下已写好的文字接着改」的时候，画布上的标注和输入控件里的文字叠成
/// 两份、还错开几个点（用户看到的「重影」就是这么来的）。
///
/// 这里把约定收紧成一条：**文字行框的左上角就是锚点**（不是墨迹的左上角——墨迹
/// 高低随字形变，行框不随）。预览与导出都从 `topLeft(of:)` 取位置，输入控件本来
/// 就是这个行为（内边距归零后，行框顶 = 视图原点）。
enum ScreenshotAnnotationText {
    /// 排版用的字体，与内联输入控件的 `applyStyle(to:)` 保持一致。
    static func font(for annotation: ScreenshotAnnotation) -> NSFont {
        let base = NSFont.systemFont(
            ofSize: annotation.fontSize,
            weight: annotation.isBold ? .semibold : .regular
        )
        guard annotation.isItalic else { return base }
        let descriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(.italic)
        )
        return NSFont(descriptor: descriptor, size: annotation.fontSize) ?? base
    }

    /// 行高：既进 `textSize` 的占位计算，也是多行文字之间推进的步长。
    static func lineHeight(fontSize: CGFloat, font: NSFont) -> CGFloat {
        max(fontSize * 1.22, font.ascender - font.descender + font.leading)
    }

    /// 文字行框左上角在画布坐标里的位置。
    ///
    /// 这就是内联输入控件自己的原点。它的逆运算（中心点 ← 左上角锚点）是
    /// `ScreenshotEditorModel.textCenter(alignedAtLeft:)`，两边是一对，必须同源；
    /// 画布视图里的 `textEditingAnchor(for:)` 只是转手调用这里。
    static func topLeft(of annotation: ScreenshotAnnotation) -> CGPoint {
        let size = annotation.textSize
        return CGPoint(
            x: annotation.start.x - size.width / 2 + 9,
            y: annotation.start.y - size.height / 2 + 9
        )
    }

    /// 在「y 向下、以画布点为单位」的 CGContext 里画出这段文字。
    ///
    /// 两个调用方都满足这个前提：预览的 SwiftUI `Canvas` 天生如此，导出管线在主
    /// 循环里先翻转过 CTM。上下文里再套一层 flipped 的 `NSGraphicsContext`，
    /// `draw(at:)` 的落点就与 `NSTextView` 里的行框一致——行框顶在锚点上、基线在
    /// 锚点 + `font.ascender` 处（AppKit 的文本绘制在非 flipped 的上下文里把给定
    /// 点当作行框左下角，那正是「预览和输入控件对不上」的根源，别再走那条路）。
    static func draw(_ annotation: ScreenshotAnnotation, in context: CGContext, opacity: CGFloat = 1) {
        guard let text = annotation.text, !text.isEmpty else { return }
        let font = font(for: annotation)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.textColor.nsColor.withAlphaComponent(opacity),
            .strikethroughStyle: annotation.isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
        ]
        let lineHeight = lineHeight(fontSize: annotation.fontSize, font: font)
        let origin = topLeft(of: annotation)

        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            NSAttributedString(string: line, attributes: attributes).draw(
                at: CGPoint(x: origin.x, y: origin.y + CGFloat(index) * lineHeight)
            )
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
