import SwiftUI

struct ScreenshotAnnotationView: View {
    let annotation: ScreenshotAnnotation
    let canvasSize: CGSize
    let mosaicImage: NSImage?
    var isDraft = false

    var body: some View {
        switch annotation.kind {
        case .arrow:
            ArrowAnnotationView(
                start: annotation.start,
                end: annotation.end,
                color: annotation.color.color,
                lineWidth: annotation.lineWidth,
                headSize: annotation.arrowHeadSize,
                headStyle: annotation.arrowHeadStyle,
                isDraft: isDraft
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .allowsHitTesting(false)
        case .rectangle:
            RectangleAnnotationView(
                start: annotation.start,
                end: annotation.end,
                color: annotation.color.color,
                lineWidth: annotation.lineWidth,
                lineStyle: annotation.lineStyle,
                isDraft: isDraft
            )
            .frame(width: canvasSize.width, height: canvasSize.height)
            .allowsHitTesting(false)
        case .mosaic:
            MosaicAnnotationView(
                points: annotation.points,
                brushSize: annotation.brushSize,
                mode: annotation.mosaicMode,
                style: annotation.mosaicStyle,
                canvasSize: canvasSize,
                mosaicImage: mosaicImage,
                isDraft: isDraft
            )
            .allowsHitTesting(false)
        case .text:
            TextAnnotationView(annotation: annotation, isDraft: isDraft)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .allowsHitTesting(false)
        }
    }
}

struct RectangleAnnotationView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let lineWidth: CGFloat
    let lineStyle: ScreenshotLineStyle
    let isDraft: Bool

    var body: some View {
        Canvas { context, _ in
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            guard rect.width > 0, rect.height > 0 else { return }
            context.stroke(
                Path(rect),
                with: .color(color.opacity(isDraft ? 0.58 : 0.96)),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .butt,
                    lineJoin: .miter,
                    dash: lineStyle.dashPattern
                )
            )
        }
    }
}

struct TextAnnotationView: View {
    let annotation: ScreenshotAnnotation
    let isDraft: Bool

    var body: some View {
        Text(annotation.text ?? "")
            .font(.system(size: annotation.fontSize, weight: annotation.isBold ? .semibold : .regular))
            .italic(annotation.isItalic)
            .strikethrough(annotation.isStrikethrough, color: annotation.textColor.color)
            .foregroundStyle(annotation.textColor.color.opacity(isDraft ? 0.62 : 1))
            .lineLimit(nil)
            .frame(width: annotation.textSize.width, height: annotation.textSize.height)
            .position(x: annotation.start.x, y: annotation.start.y)
    }
}

struct ArrowAnnotationView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let lineWidth: CGFloat
    let headSize: CGFloat
    let headStyle: ScreenshotArrowHeadStyle
    let isDraft: Bool

    var body: some View {
        Canvas { context, _ in
            let strokeColor = color.opacity(isDraft ? 0.58 : 0.96)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength = max(headSize, lineWidth * 2.6)
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let perpendicular = CGPoint(x: -direction.y, y: direction.x)
            let headBase = CGPoint(
                x: end.x - direction.x * headLength,
                y: end.y - direction.y * headLength
            )

            var line = Path()
            line.move(to: start)
            line.addLine(to: headStyle == .none ? end : headBase)
            context.stroke(
                line,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            guard headStyle != .none else { return }
            let halfWidth = headLength * 0.34
            let left = CGPoint(
                x: headBase.x + perpendicular.x * halfWidth,
                y: headBase.y + perpendicular.y * halfWidth
            )
            let right = CGPoint(
                x: headBase.x - perpendicular.x * halfWidth,
                y: headBase.y - perpendicular.y * halfWidth
            )
            var head = Path()
            head.move(to: end)
            head.addLine(to: left)
            head.addLine(to: right)
            head.closeSubpath()
            context.fill(head, with: .color(strokeColor))
        }
    }
}

struct MosaicAnnotationView: View {
    let points: [CGPoint]
    let brushSize: CGFloat
    let mode: ScreenshotMosaicMode
    let style: ScreenshotMosaicStyle
    let canvasSize: CGSize
    let mosaicImage: NSImage?
    let isDraft: Bool

    var body: some View {
        ZStack {
            if let mosaicImage {
                Image(nsImage: mosaicImage)
                    .resizable()
                    .interpolation(style == .pixelate ? .none : .high)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .mask(mosaicMask.fill(.white))
            } else {
                mosaicMask
                    .fill(Color.black.opacity(isDraft ? 0.2 : 0.62))
            }

            if isDraft {
                if mode == .brush {
                    FreehandStroke(points: points)
                        .stroke(
                            Color.jarvisCyan.opacity(0.92),
                            style: StrokeStyle(
                                lineWidth: max(brushSize, 2),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                } else {
                    mosaicMask
                        .stroke(Color.jarvisCyan.opacity(0.92), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private var mosaicMask: some Shape {
        if mode == .brush {
            return AnyShape(FreehandStrokeArea(points: points, lineWidth: max(brushSize, 2)))
        }
        return AnyShape(MosaicRectangleShape(start: points.first ?? .zero, end: points.last ?? .zero))
    }
}

struct MosaicRectangleShape: Shape {
    let start: CGPoint
    let end: CGPoint

    func path(in _: CGRect) -> Path {
        Path(
            CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
        )
    }
}

struct FreehandStroke: Shape {
    let points: [CGPoint]

    func path(in _: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

struct FreehandStrokeArea: Shape {
    let points: [CGPoint]
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        FreehandStroke(points: points)
            .path(in: rect)
            .strokedPath(
                StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }
}
