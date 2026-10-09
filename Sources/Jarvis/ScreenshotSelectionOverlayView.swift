import AppKit

final class SelectionOverlayView: NSView {
    /// 只把变化的那块标脏。
    ///
    /// 原来每次都 `needsDisplay = true`，而 `draw` 又忽略 `dirtyRect` 直接填满整屏：
    /// 6K 上拖选就是每个鼠标事件一次两千多万像素的填充+合成。这里只把新旧选区
    /// （含尺寸标签）的并集标脏，AppKit 会把绘制裁到那块。
    private func invalidateSelectionArea(_ rects: CGRect?...) {
        var dirty = CGRect.null
        var sawRect = false
        for rect in rects {
            if let rect {
                sawRect = true
                dirty = dirty.union(rect.insetBy(dx: -32, dy: -32))
            }
        }
        // 点下去还没拖开时三个矩形都是 nil。这里不能退回整屏重画，
        // 否则每次轻微移动都会在 6K 上填满一帧。
        guard sawRect else { return }
        guard !dirty.isNull, !dirty.isInfinite else {
            needsDisplay = true
            return
        }
        setNeedsDisplay(dirty.intersection(bounds))
    }

    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onPin: ((CGRect) -> Void)?

    private let frozenCGImage: CGImage?
    private let windowCandidates: [WindowSelectionCandidate]
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var movedSelectionRect: CGRect?
    private var moveAnchor: CGPoint?
    private var hoveredWindowCandidate: WindowSelectionCandidate?
    private var windowCandidateAtMouseDown: WindowSelectionCandidate?
    private var didDragSelection = false
    private var spacePressed = false

    init(
        frame frameRect: NSRect,
        frozenCGImage: CGImage?,
        windowCandidates: [WindowSelectionCandidate]
    ) {
        self.frozenCGImage = frozenCGImage
        self.windowCandidates = windowCandidates
        super.init(frame: frameRect)
        wantsLayer = true
        updateTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    private var selectionTrackingArea: NSTrackingArea?

    private func updateTrackingArea() {
        if let selectionTrackingArea {
            removeTrackingArea(selectionTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        selectionTrackingArea = trackingArea
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        updateTrackingArea()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        updateHoveredWindowCandidate(at: convert(windowPoint, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        // 防御性冗余说明：Esc（JarvisKeyCode.escape）实际由宿主窗口 sendEvent 先行拦截
        // 并回调 onCancel，这里的 Esc 分支正常走不到，仅作视图被挪到普通窗口
        // 时的兜底。
        if event.keyCode == JarvisKeyCode.escape {
            onCancel?()
        } else if event.keyCode == JarvisKeyCode.space {
            spacePressed = true
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == JarvisKeyCode.space {
            spacePressed = false
        } else {
            super.keyUp(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        movedSelectionRect = nil
        moveAnchor = nil
        didDragSelection = false
        windowCandidateAtMouseDown = updateHoveredWindowCandidate(at: startPoint)
    }

    func pinHoveredWindow() {
        let pointerCandidate: WindowSelectionCandidate?
        if let window {
            let screenPoint = NSEvent.mouseLocation
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let localPoint = convert(windowPoint, from: nil)
            pointerCandidate = windowCandidate(at: localPoint)
        } else {
            pointerCandidate = nil
        }
        guard let candidate = pointerCandidate ?? hoveredWindowCandidate else { return }
        resetPointerState()
        onPin?(candidate.localRect)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var clearedWindowRect: CGRect?
        if let startPoint,
           hypot(point.x - startPoint.x, point.y - startPoint.y) > 4
        {
            if !didDragSelection {
                clearedWindowRect = hoveredWindowCandidate?.localRect
            }
            didDragSelection = true
            hoveredWindowCandidate = nil
        }
        if spacePressed, let selectionRect {
            if moveAnchor == nil {
                movedSelectionRect = selectionRect
                moveAnchor = point
            } else if let moveAnchor, var movedSelectionRect {
                movedSelectionRect.origin.x += point.x - moveAnchor.x
                movedSelectionRect.origin.y += point.y - moveAnchor.y
                self.movedSelectionRect = clampedRect(movedSelectionRect)
                self.moveAnchor = point
            }
        } else {
            let previous = visibleSelectionRect
            currentPoint = point
            invalidateSelectionArea(clearedWindowRect, previous, visibleSelectionRect)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !didDragSelection,
           !spacePressed,
           let windowCandidateAtMouseDown
        {
            resetPointerState()
            onFinish?(windowCandidateAtMouseDown.localRect)
            return
        }
        if spacePressed, let selectionRect, let moveAnchor {
            var movedSelectionRect = selectionRect
            movedSelectionRect.origin.x += point.x - moveAnchor.x
            movedSelectionRect.origin.y += point.y - moveAnchor.y
            self.movedSelectionRect = clampedRect(movedSelectionRect)
        } else {
            currentPoint = point
        }
        guard let selection = selectionRect else {
            resetPointerState()
            onCancel?()
            return
        }
        resetPointerState()
        onFinish?(selection)
    }

    override func mouseMoved(with event: NSEvent) {
        guard startPoint == nil, movedSelectionRect == nil, moveAnchor == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        _ = updateHoveredWindowCandidate(at: point)
    }

    @discardableResult
    private func updateHoveredWindowCandidate(at point: CGPoint?) -> WindowSelectionCandidate? {
        let candidate = windowCandidate(at: point)
        let changed = candidate?.windowID != hoveredWindowCandidate?.windowID
            || candidate?.localRect != hoveredWindowCandidate?.localRect
        if changed {
            let previous = hoveredWindowCandidate?.localRect
            hoveredWindowCandidate = candidate
            invalidateSelectionArea(previous, candidate?.localRect)
        }
        return candidate
    }

    override var isOpaque: Bool {
        frozenCGImage != nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw the freeze-frame at the view's point size with nearest-neighbor
        // sampling. The previous path used NSImage.cgImage(forProposedRect:)
        // which rasterized at 1x and looked like edge zooming on Retina.
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        if let frozenCGImage {
            context.draw(frozenCGImage, in: bounds)
        } else {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(dirtyRect)
        }

        // Dim the frozen pixels with an even-odd path so the selection hole
        // still shows the freeze-frame, not the live desktop underneath.
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let visibleSelectionRect {
            dimPath.addRect(visibleSelectionRect)
        }
        context.saveGState()
        context.addPath(dimPath)
        context.setFillColor(NSColor.black.withAlphaComponent(0.46).cgColor)
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        if let visibleSelectionRect {
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(2)
            context.stroke(visibleSelectionRect)

            drawDimensionLabel(in: visibleSelectionRect, context: context)
        } else if let hoveredWindowCandidate {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(3)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(hoveredWindowCandidate.localRect.insetBy(dx: 1.5, dy: 1.5))
            context.restoreGState()
            drawDimensionLabel(in: hoveredWindowCandidate.localRect, context: context)
        }
    }

    /// 鼠标按下、还没拖开时，起点和当前点重合，几何选区是 0×0。
    /// 点选窗口会走这条路径，不能把它画出来，否则点击处会冒出「0 × 0」。
    private var visibleSelectionRect: CGRect? {
        ScreenshotSelectionChrome.marqueeRect(
            movedRect: movedSelectionRect,
            dragRect: selectionRect,
            didDrag: didDragSelection
        )
    }

    private var selectionRect: CGRect? {
        if let movedSelectionRect {
            return movedSelectionRect
        }
        guard let startPoint, let currentPoint else { return nil }
        return clampedRect(CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        ))
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func windowCandidate(at point: CGPoint?) -> WindowSelectionCandidate? {
        guard let point else { return nil }
        return windowCandidates.first(where: { $0.localRect.contains(point) })
    }

    private func resetPointerState() {
        startPoint = nil
        currentPoint = nil
        movedSelectionRect = nil
        moveAnchor = nil
        windowCandidateAtMouseDown = nil
        didDragSelection = false
    }

    private func drawDimensionLabel(in rect: CGRect, context _: CGContext) {
        guard let text = ScreenshotSelectionChrome.dimensionText(for: rect) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: rect.minX,
            y: max(8, rect.minY - size.height - 12),
            width: size.width + 16,
            height: size.height + 8
        )
        NSColor.systemBlue.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: labelRect.minX + 8, y: labelRect.minY + 4), withAttributes: attributes)
    }
}

enum ScreenshotSelectionChrome {
    /// 按下还没拖开时，几何选区是 0×0。点选窗口会走这条路径，不能把它画成框选。
    static func marqueeRect(
        movedRect: CGRect?,
        dragRect: CGRect?,
        didDrag: Bool
    ) -> CGRect? {
        if let movedRect {
            return movedRect
        }
        guard didDrag, let dragRect else { return nil }
        guard dragRect.width >= 1 || dragRect.height >= 1 else { return nil }
        return dragRect
    }

    /// 宽高都不到 1 点时不写尺寸。`Int` 会把这种选区收成「0 × 0」。
    static func dimensionText(for rect: CGRect) -> String? {
        guard rect.width >= 1 || rect.height >= 1 else { return nil }
        return "\(Int(rect.width)) × \(Int(rect.height))"
    }
}
