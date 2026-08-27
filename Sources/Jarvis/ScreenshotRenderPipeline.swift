import AppKit
import CoreGraphics

struct ScreenshotRenderRequest {
    let image: NSImage
    let canvasSize: CGSize
    let pixelScale: CGFloat
    let annotations: [ScreenshotAnnotation]
    let blurredImage: NSImage?
    let pixelatedImage: NSImage?
    let translations: [ScreenshotTranslationRenderBlock]
    let showsTranslation: Bool

    init(
        image: NSImage,
        canvasSize: CGSize,
        pixelScale: CGFloat,
        annotations: [ScreenshotAnnotation],
        blurredImage: NSImage?,
        pixelatedImage: NSImage?,
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
    func renderFullCanvas(_ request: ScreenshotRenderRequest) -> Data? {
        guard let baseImage = cgImage(from: request.image),
              request.canvasSize.width > 0,
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

        for annotation in request.annotations {
            guard annotation.kind != .text else { continue }
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
                break
            }
            context.restoreGState()
        }

        for annotation in request.annotations where annotation.kind == .text {
            drawText(annotation, in: context, canvasSize: request.canvasSize, scale: scale)
        }

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

        guard let renderedImage = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: renderedImage)
            .representation(using: .png, properties: [:])
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
        blurredImage: NSImage?,
        pixelatedImage: NSImage?
    ) {
        let image: NSImage? = switch annotation.mosaicStyle {
        case .blur: blurredImage
        case .pixelate: pixelatedImage
        }
        guard let image, let filteredImage = cgImage(from: image) else { return }

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
        context.draw(filteredImage, in: canvasRect)
        context.restoreGState()
    }

    private func drawText(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext,
        canvasSize: CGSize,
        scale: CGFloat
    ) {
        guard let text = annotation.text, !text.isEmpty else { return }

        let baseFont = NSFont.systemFont(
            ofSize: annotation.fontSize,
            weight: annotation.isBold ? .semibold : .regular
        )
        var descriptor = baseFont.fontDescriptor
        if annotation.isItalic {
            var traits = descriptor.symbolicTraits
            traits.insert(.italic)
            descriptor = descriptor.withSymbolicTraits(traits)
        }
        let font = NSFont(descriptor: descriptor, size: annotation.fontSize) ?? baseFont
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.textColor.nsColor,
            .strikethroughStyle: annotation.isStrikethrough ? NSUnderlineStyle.single.rawValue : 0
        ]
        let textSize = annotation.textSize
        let lines = text.components(separatedBy: "\n")
        let lineHeight = max(
            annotation.fontSize * 1.22,
            font.ascender - font.descender + font.leading
        )
        let top = annotation.start.y - textSize.height / 2 + 9
        let left = annotation.start.x - textSize.width / 2 + 9

        context.saveGState()
        // The previous canvas pass restored the context to its identity
        // transform. Text is drawn in the native bottom-left coordinate
        // system, scaled back to logical points for AppKit typography.
        context.scaleBy(x: scale, y: scale)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        for (index, line) in lines.enumerated() {
            let lineWidth = (line as NSString).size(withAttributes: attributes).width
            let baselineY = canvasSize.height - (top + font.ascender + CGFloat(index) * lineHeight)
            NSAttributedString(string: line, attributes: attributes)
                .draw(at: NSPoint(x: left, y: baselineY))

            if annotation.isStrikethrough {
                annotation.textColor.nsColor.setStroke()
                let strikeY = baselineY + font.pointSize * 0.28
                let path = NSBezierPath()
                path.move(to: NSPoint(x: left, y: strikeY))
                path.line(to: NSPoint(x: left + lineWidth, y: strikeY))
                path.lineWidth = max(1, annotation.fontSize / 14)
                path.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
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

        let fontSize = max(11, min(28, bounds.height * 0.62))
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let padding: CGFloat = 6
        let textRect = CGRect(
            x: bounds.minX + padding,
            y: bounds.minY + padding,
            width: max(1, bounds.width - padding * 2),
            height: max(1, bounds.height - padding * 2)
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
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        let flippedTextRect = NSRect(
            x: textRect.minX,
            y: canvasSize.height - textRect.maxY,
            width: textRect.width,
            height: textRect.height
        )
        NSAttributedString(string: translation.translatedText, attributes: attributes)
            .draw(
                with: flippedTextRect,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}

private extension ScreenshotTextColor {
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
