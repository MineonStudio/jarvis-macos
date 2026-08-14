import AppKit

final class SelectionOverlayView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onPin: ((CGRect) -> Void)?

    private let frozenImage: NSImage
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
        frozenImage: NSImage,
        windowCandidates: [WindowSelectionCandidate]
    ) {
        self.frozenImage = frozenImage
        var proposedRect = NSRect(origin: .zero, size: frozenImage.size)
        frozenCGImage = frozenImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        )
        self.windowCandidates = windowCandidates
        super.init(frame: frameRect)
        updateTrackingArea()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
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
        if event.keyCode == 53 {
            onCancel?()
        } else if event.keyCode == 49 {
            spacePressed = true
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
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
        needsDisplay = true
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
        if let startPoint,
           hypot(point.x - startPoint.x, point.y - startPoint.y) > 4
        {
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
            currentPoint = point
        }
        needsDisplay = true
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
            hoveredWindowCandidate = candidate
            needsDisplay = true
        }
        return candidate
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.interpolationQuality = .high
        if let frozenCGImage {
            context.draw(frozenCGImage, in: bounds)
        } else {
            frozenImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        }
        context.setFillColor(NSColor.black.withAlphaComponent(0.58).cgColor)
        context.fill(bounds)

        if let selectionRect {
            context.saveGState()
            context.clip(to: selectionRect)
            if let frozenCGImage {
                context.draw(frozenCGImage, in: bounds)
            } else {
                frozenImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            }
            context.restoreGState()

            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(2)
            context.stroke(selectionRect)

            drawDimensionLabel(in: selectionRect, context: context)
        } else if let hoveredWindowCandidate {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(3)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(hoveredWindowCandidate.localRect.insetBy(dx: 1.5, dy: 1.5))
            context.restoreGState()
        }

        drawHint(in: bounds, context: context)
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

    private func drawHint(in bounds: CGRect, context _: CGContext) {
        guard selectionRect == nil else { return }
        let text = hoveredWindowCandidate == nil
            ? "悬停窗口后单击自动选中  ·  拖动自定义框选  ·  ESC 取消"
            : "单击选中窗口  ·  拖动自定义框选  ·  ESC 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let size = text.size(withAttributes: attributes)
        let rect = CGRect(
            x: bounds.midX - size.width / 2 - 14,
            y: bounds.maxY - 70,
            width: size.width + 28,
            height: size.height + 14
        )
        NSColor.black.withAlphaComponent(0.52).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        text.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 7), withAttributes: attributes)
    }

    private func drawDimensionLabel(in rect: CGRect, context _: CGContext) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
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
