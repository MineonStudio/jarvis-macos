import AppKit
import CoreGraphics

/// 渲染所需的全部输入。
///
/// 图都用 `CGImage` 而不是 `NSImage`：渲染整段跑在后台任务上（6K 画布上这一步是
/// 秒级），而 `NSImage` 不是 Sendable，`CGImage` 是。
struct ScreenshotRenderRequest: Sendable {
    let image: CGImage
    let canvasSize: CGSize
    let pixelScale: CGFloat
    let annotations: [ScreenshotAnnotation]
    let blurredImage: CGImage?
    let pixelatedImage: CGImage?
    let translations: [ScreenshotTranslationRenderBlock]
    let showsTranslation: Bool

    init(
        image: CGImage,
        canvasSize: CGSize,
        pixelScale: CGFloat,
        annotations: [ScreenshotAnnotation],
        blurredImage: CGImage?,
        pixelatedImage: CGImage?,
        translations: [ScreenshotTranslationRenderBlock] = [],
        showsTranslation: Bool = false
    ) {
        self.image = image
        self.canvasSize = canvasSize
        self.pixelScale = pixelScale
        self.annotations = annotations
        self.blurredImage = blurredImage
        self.pixelatedImage = pixelatedImage
        self.translations = translations
        self.showsTranslation = showsTranslation
    }
}

/// Renders the final screenshot independently from the interactive SwiftUI
/// canvas. SwiftUI remains responsible for preview and gestures; export uses
/// one deterministic Core Graphics pass so the final image does not depend on
/// view layout or transient editor state.
final class ScreenshotRenderPipeline {
    /// 渲染整幅画布。返回位图而不是 PNG——调用方多数只要其中一块，先编码整幅
    /// 再解码回来裁，是 6K 图上秒级的无用功。
    func renderFullCanvas(_ request: ScreenshotRenderRequest) -> CGImage? {
        let baseImage = request.image
        guard request.canvasSize.width > 0,
              request.canvasSize.height > 0
        else {
            return nil
        }

        let scale = max(request.pixelScale, 1)
        let pixelWidth = max(1, Int((request.canvasSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((request.canvasSize.height * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let canvasRect = CGRect(origin: .zero, size: request.canvasSize)
        context.interpolationQuality = .high
        context.saveGState()
        // The bitmap context is measured in physical pixels. Draw the source
        // image in logical canvas points after applying the Retina scale;
        // otherwise edited exports only occupy the top-left 1x portion of a
        // 2x canvas before the final crop is applied.
        context.scaleBy(x: scale, y: scale)
        context.draw(baseImage, in: canvasRect)
        context.restoreGState()

        if request.showsTranslation {
            for translation in request.translations {
                drawTranslation(
                    translation,
                    in: context,
                    canvasSize: request.canvasSize,
                    pixelHeight: pixelHeight,
                    scale: scale
                )
            }
        }

        for annotation in request.annotations {
            context.saveGState()
            // Annotation points come from the SwiftUI canvas (top-left
            // origin), while the exported bitmap keeps the source image's
            // native bottom-left pixel coordinates.
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: scale, y: -scale)
            switch annotation.kind {
            case .arrow:
                drawArrow(annotation, in: context)
            case .rectangle:
                drawRectangle(annotation, in: context)
            case .mosaic:
                drawMosaic(
                    annotation,
                    in: context,
                    canvasRect: canvasRect,
                    blurredImage: request.blurredImage,
                    pixelatedImage: request.pixelatedImage
                )
            case .text:
                // 文字和别的标注一样走这条翻转过 CTM 的通道，位置由
                // `ScreenshotAnnotationText` 统一给出——预览和输入控件用的是同一份。
                // 它也因此和别的标注一样按数组顺序叠：导出与预览的上下层关系一致
                // （原来文字单独留到最后画，永远压在所有标注之上）。
                ScreenshotAnnotationText.draw(annotation, in: context)
            }
            context.restoreGState()
        }

        return context.makeImage()
    }

    private func drawArrow(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        let start = annotation.start
        let end = annotation.end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(annotation.arrowHeadSize, annotation.lineWidth * 2.6)
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)
        let headBase = CGPoint(
            x: end.x - direction.x * headLength,
            y: end.y - direction.y * headLength
        )
        let lineEnd = annotation.arrowHeadStyle == .none ? end : headBase
        let color = annotation.color.nsColor.withAlphaComponent(0.96).cgColor

        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: start)
        context.addLine(to: lineEnd)
        context.strokePath()

        if annotation.arrowHeadStyle != .none {
            let halfWidth = headLength * 0.34
            let left = CGPoint(
                x: headBase.x + perpendicular.x * halfWidth,
                y: headBase.y + perpendicular.y * halfWidth
            )
            let right = CGPoint(
                x: headBase.x - perpendicular.x * halfWidth,
                y: headBase.y - perpendicular.y * halfWidth
            )
            context.setFillColor(color)
            context.move(to: end)
            context.addLine(to: left)
            context.addLine(to: right)
            context.closePath()
            context.fillPath()
        }
        context.restoreGState()
    }

    private func drawRectangle(_ annotation: ScreenshotAnnotation, in context: CGContext) {
        let rect = CGRect(
            x: min(annotation.start.x, annotation.end.x),
            y: min(annotation.start.y, annotation.end.y),
            width: abs(annotation.end.x - annotation.start.x),
            height: abs(annotation.end.y - annotation.start.y)
        )
        guard rect.width > 0, rect.height > 0 else { return }

        context.saveGState()
        context.setStrokeColor(annotation.color.nsColor.withAlphaComponent(0.96).cgColor)
        context.setLineWidth(annotation.lineWidth)
        context.setLineCap(.butt)
        context.setLineJoin(.miter)
        context.setLineDash(phase: 0, lengths: annotation.lineStyle.dashPattern)
        context.stroke(rect)
        context.restoreGState()
    }

    private func drawMosaic(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext,
        canvasRect: CGRect,
        blurredImage: CGImage?,
        pixelatedImage: CGImage?
    ) {
        let filteredImage: CGImage? = switch annotation.mosaicStyle {
        case .blur: blurredImage
        case .pixelate: pixelatedImage
        }
        guard let filteredImage else { return }

        context.saveGState()
        switch annotation.mosaicMode {
        case .rectangle:
            let rect = CGRect(
                x: min(annotation.start.x, annotation.end.x),
                y: min(annotation.start.y, annotation.end.y),
                width: abs(annotation.end.x - annotation.start.x),
                height: abs(annotation.end.y - annotation.start.y)
            )
            guard rect.width > 0, rect.height > 0 else {
                context.restoreGState()
                return
            }
            context.clip(to: rect)
        case .brush:
            guard annotation.points.count > 1 else {
                context.restoreGState()
                return
            }
            let path = CGMutablePath()
            path.move(to: annotation.points[0])
            for point in annotation.points.dropFirst() {
                path.addLine(to: point)
            }
            context.addPath(path)
            context.setLineWidth(max(annotation.brushSize, 2))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
        }

        context.interpolationQuality = annotation.mosaicStyle == .pixelate ? .none : .high
        // 这里的 CTM 是 y 向下（标注坐标来自左上角原点的画布），而
        // `CGContext.draw(image:in:)` 总是把图像按当前用户空间正立绘制——在翻转
        // 空间里画出来就是上下镜像的。底图和文字各自处理过这一点，马赛克原来漏了：
        // 框住顶部的内容，导出后框里显示的是镜像位置的画面。clip 已经固定到设备
        // 空间，所以补的这一层反向翻转只影响图像本身落笔的方向。
        context.translateBy(x: 0, y: canvasRect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(filteredImage, in: canvasRect)
        context.restoreGState()
    }

    private func drawTranslation(
        _ translation: ScreenshotTranslationRenderBlock,
        in context: CGContext,
        canvasSize: CGSize,
        pixelHeight: Int,
        scale: CGFloat
    ) {
        let bounds = translation.bounds.integral
        guard bounds.width > 4, bounds.height > 4 else { return }

        let fontSize = max(1, translation.fontSize > 0 ? translation.fontSize : bounds.height - 2)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let horizontalPadding = max(0, translation.horizontalPadding)
        let displayLines = translation.displayLines.isEmpty
            ? [translation.translatedText]
            : Array(translation.displayLines.prefix(max(1, translation.lineLimit)))
        let displayLineBounds = translationLineBounds(
            for: displayLines,
            translation: translation,
            bounds: bounds,
            lineHeight: ScreenshotTranslationTextLayout.measuredLineHeight(fontSize: fontSize)
        )
        let textRect = CGRect(
            x: bounds.minX + horizontalPadding,
            y: bounds.minY,
            width: max(1, bounds.width - horizontalPadding * 2),
            height: max(1, bounds.height)
        )

        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        context.addPath(CGPath(
            roundedRect: bounds,
            cornerWidth: min(8, bounds.height / 3),
            cornerHeight: min(8, bounds.height / 3),
            transform: nil
        ))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.clip(to: CGRect(
            x: textRect.minX,
            y: canvasSize.height - textRect.maxY,
            width: textRect.width,
            height: textRect.height
        ))
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        for (index, line) in displayLines.enumerated() {
            let lineBounds = displayLineBounds[index]
            let baselineY = canvasSize.height - (lineBounds.minY + font.ascender)
            NSAttributedString(string: line, attributes: attributes)
                .draw(at: NSPoint(x: lineBounds.minX + horizontalPadding, y: baselineY))
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}

private func translationLineBounds(
    for lines: [String],
    translation: ScreenshotTranslationRenderBlock,
    bounds: CGRect,
    lineHeight: CGFloat
) -> [CGRect] {
    guard translation.displayLineBounds.count >= lines.count else {
        let height = max(8, bounds.height / CGFloat(lines.count))
        return lines.indices.map { index in
            CGRect(
                x: bounds.minX,
                y: bounds.minY + CGFloat(index) * height,
                width: bounds.width,
                height: height
            )
        }
    }
    return Array(translation.displayLineBounds.prefix(lines.count)).map { line in
        CGRect(
            x: line.minX,
            y: line.minY,
            width: bounds.width,
            height: max(line.height, lineHeight)
        )
    }
}

extension ScreenshotTextColor {
    var nsColor: NSColor {
        switch self {
        case .red: NSColor(red: 1, green: 0.12, blue: 0.12, alpha: 1)
        case .yellow: .systemYellow
        case .white: .white
        case .black: .black
        case .cyan: .cyan
        case .blue: NSColor(red: 0.1, green: 0.38, blue: 0.95, alpha: 1)
        case .green: NSColor(red: 0.12, green: 0.62, blue: 0.25, alpha: 1)
        }
    }
}
