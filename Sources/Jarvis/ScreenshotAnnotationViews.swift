import SwiftUI

struct ScreenshotAnnotationView: View {
    let annotation: ScreenshotAnnotation
    let canvasSize: CGSize
    let mosaicImage: NSImage?
    var isDraft = false

    /// 标注自己的外接矩形（画布坐标，含线宽/箭头/笔触的余量）。
    ///
    /// 每个标注原来都铺满整个画布：6K 画布下一个马赛克框的 mask 就是 81MB，几个框
    /// 叠起来几百 MB。收窄到自己那一块之后，占用只跟标注本身的大小有关。
    var scopedBounds: CGRect {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        // 余量按种类取：马赛克看笔触宽度，箭头还要留出箭头本身，其余就是线宽。
        let margin = (annotation.kind == .mosaic ? annotation.brushSize : annotation.lineWidth)
            + (annotation.kind == .arrow ? annotation.arrowHeadSize / 2 : 0)
            + 8
        let content: CGRect = switch annotation.kind {
        case .text:
            CGRect(
                x: annotation.start.x - annotation.textSize.width / 2,
                y: annotation.start.y - annotation.textSize.height / 2,
                width: annotation.textSize.width,
                height: annotation.textSize.height
            )
        case .arrow, .rectangle, .mosaic:
            annotation.canvasBounds
        }
        return content.insetBy(dx: -margin, dy: -margin).intersection(canvas)
    }

    var body: some View {
        let bounds = scopedBounds
        let origin = bounds.origin

        Group {
            switch annotation.kind {
            case .arrow:
                ArrowAnnotationView(
                    start: annotation.start,
                    end: annotation.end,
                    color: annotation.color.color,
                    lineWidth: annotation.lineWidth,
                    headSize: annotation.arrowHeadSize,
                    headStyle: annotation.arrowHeadStyle,
                    origin: origin,
                    isDraft: isDraft
                )
            case .rectangle:
                RectangleAnnotationView(
                    start: annotation.start,
                    end: annotation.end,
                    color: annotation.color.color,
                    lineWidth: annotation.lineWidth,
                    lineStyle: annotation.lineStyle,
                    origin: origin,
                    isDraft: isDraft
                )
            case .mosaic:
                MosaicAnnotationView(
                    points: annotation.points,
                    brushSize: annotation.brushSize,
                    mode: annotation.mosaicMode,
                    style: annotation.mosaicStyle,
                    canvasSize: canvasSize,
                    mosaicImage: mosaicImage,
                    origin: origin,
                    size: bounds.size,
                    isDraft: isDraft
                )
            case .text:
                TextAnnotationView(annotation: annotation, origin: origin, isDraft: isDraft)
            }
        }
        // 图层只有标注那么大，再平移回它在画布上的位置（ZStack 是左上对齐）。
        .frame(width: bounds.width, height: bounds.height)
        .offset(x: origin.x, y: origin.y)
        .allowsHitTesting(false)
    }
}

struct RectangleAnnotationView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let lineWidth: CGFloat
    let lineStyle: ScreenshotLineStyle
    /// 这一块在画布里的原点：绘制都按局部坐标走。
    let origin: CGPoint
    let isDraft: Bool

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: -origin.x, y: -origin.y)
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
    /// 这一块在画布里的原点：绘制都按局部坐标走。
    let origin: CGPoint
    let isDraft: Bool

    var body: some View {
        Text(verbatim: annotation.text ?? "")
            .font(.system(size: annotation.fontSize, weight: annotation.isBold ? .semibold : .regular))
            .italic(annotation.isItalic)
            .strikethrough(annotation.isStrikethrough, color: annotation.textColor.color)
            .foregroundStyle(annotation.textColor.color.opacity(isDraft ? 0.62 : 1))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .frame(width: annotation.textSize.width, height: annotation.textSize.height)
            .position(
                x: annotation.start.x - origin.x,
                y: annotation.start.y - origin.y
            )
    }
}

struct ArrowAnnotationView: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let lineWidth: CGFloat
    let headSize: CGFloat
    let headStyle: ScreenshotArrowHeadStyle
    /// 这一块在画布里的原点：绘制都按局部坐标走。
    let origin: CGPoint
    let isDraft: Bool

    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: -origin.x, y: -origin.y)
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
    /// 这一块在画布里的原点：绘制都按局部坐标走。
    let origin: CGPoint
    /// 这一块的尺寸。收进这个尺寸里再裁掉溢出，图层才真的只有这么大。
    let size: CGSize
    let isDraft: Bool

    var body: some View {
        ZStack {
            if let mosaicImage {
                Image(nsImage: mosaicImage)
                    .resizable()
                    .interpolation(style == .pixelate ? .none : .high)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .offset(x: -origin.x, y: -origin.y)
                    // 过滤图是整幅画布大小的：不把它收进这一块并裁掉溢出，整个视图
                    // 会被撑成画布尺寸，外层的 frame 收不住，马赛克就被摆到画布
                    // 左上角去了。
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .mask(mosaicMask.fill(.white).offset(x: -origin.x, y: -origin.y))
            } else {
                mosaicMask
                    .fill(Color.black.opacity(isDraft ? 0.2 : 0.62))
                    .offset(x: -origin.x, y: -origin.y)
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
                        .offset(x: -origin.x, y: -origin.y)
                } else {
                    mosaicMask
                        .stroke(Color.jarvisCyan.opacity(0.92), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .offset(x: -origin.x, y: -origin.y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
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
