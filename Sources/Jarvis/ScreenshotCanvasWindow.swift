import AppKit
import SwiftUI

// MARK: - Screenshot canvas window

final class ScreenshotImagePanel: NSPanel {
    var onDoubleClick: (() -> Void)?
    var onMiddleClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            onEscape?()
            return
        }
        if event.type == .leftMouseDown,
           event.clickCount == 2,
           let onDoubleClick
        {
            onDoubleClick()
            return
        }
        if event.type == .otherMouseDown,
           event.buttonNumber == 2,
           let onMiddleClick
        {
            onMiddleClick()
            return
        }
        super.sendEvent(event)
    }
}

final class ScreenshotCanvasHostingView: NSHostingView<ScreenshotCanvasView> {
    private let editor: ScreenshotEditorModel
    private let allowsSelectionTransform: Bool
    private let onActivate: (() -> Void)?
    private let onDoubleClick: (() -> Void)?
    private let onMiddleClick: (() -> Void)?
    private let onEscape: (() -> Void)?
    private enum ResizeHandle {
        case topLeading
        case top
        case topTrailing
        case trailing
        case bottomTrailing
        case bottom
        case bottomLeading
        case leading
    }

    private enum SelectionInteraction {
        case move
        case resize(ResizeHandle)
    }

    private var selectionInteraction: SelectionInteraction?
    private var selectionStartRect: CGRect?
    private var selectionStartPoint: CGPoint?
    private var initialWindowOrigin: NSPoint?
    private var initialMouseLocation: NSPoint?

    init(
        rootView: ScreenshotCanvasView,
        editor: ScreenshotEditorModel,
        allowsSelectionTransform: Bool = true,
        onActivate: (() -> Void)? = nil,
        onDoubleClick: (() -> Void)? = nil,
        onMiddleClick: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil
    ) {
        self.editor = editor
        self.allowsSelectionTransform = allowsSelectionTransform
        self.onActivate = onActivate
        self.onDoubleClick = onDoubleClick
        self.onMiddleClick = onMiddleClick
        self.onEscape = onEscape
        super.init(rootView: rootView)
    }

    @MainActor
    required init(rootView: ScreenshotCanvasView) {
        editor = rootView.editor
        allowsSelectionTransform = true
        onActivate = nil
        onDoubleClick = nil
        onMiddleClick = nil
        onEscape = nil
        super.init(rootView: rootView)
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape {
            onEscape()
            return
        }

        let commandPressed = event.modifierFlags.contains(.command)
        let shiftPressed = event.modifierFlags.contains(.shift)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if editor.selectedAnnotationID != nil,
           event.keyCode == 51 || event.keyCode == 117
        {
            editor.deleteSelectedAnnotation()
            return
        }

        if commandPressed, characters == "d" {
            editor.duplicateSelectedAnnotation()
            return
        }

        if commandPressed, characters == "z" {
            if shiftPressed {
                editor.redo()
            } else {
                editor.undo()
            }
            return
        }

        if event.keyCode == 53, editor.selectedAnnotationID != nil {
            editor.clearSelection()
            return
        }

        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .otherMouseDown, event.buttonNumber == 2 {
            onMiddleClick?()
            return
        }

        onActivate?()

        if allowsSelectionTransform,
           editor.selectedTool == nil,
           let selectionRect = editor.selectionRect
        {
            let canvasPoint = canvasPoint(for: event)
            if let interaction = selectionInteraction(at: canvasPoint, in: selectionRect) {
                selectionInteraction = interaction
                selectionStartRect = selectionRect
                selectionStartPoint = canvasPoint
                return
            }
        }

        guard editor.selectedTool == nil,
              allowsSelectionTransform ? editor.editingRect == nil : true,
              let window
        else {
            super.mouseDown(with: event)
            return
        }
        initialWindowOrigin = window.frame.origin
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onMiddleClick?()
            return
        }
        super.otherMouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if let selectionInteraction,
           let selectionStartRect,
           let selectionStartPoint
        {
            let currentPoint = canvasPoint(for: event)
            let delta = CGSize(
                width: currentPoint.x - selectionStartPoint.x,
                height: currentPoint.y - selectionStartPoint.y
            )
            let updatedRect: CGRect = switch selectionInteraction {
            case .move:
                movedRect(selectionStartRect, by: delta)
            case let .resize(handle):
                resizedRect(selectionStartRect, handle: handle, by: delta)
            }
            editor.updateSelectionRect(updatedRect)
            return
        }

        guard editor.selectedTool == nil,
              editor.editingRect == nil,
              let window,
              let initialWindowOrigin,
              let initialMouseLocation
        else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: initialWindowOrigin.x + currentMouseLocation.x - initialMouseLocation.x,
                y: initialWindowOrigin.y + currentMouseLocation.y - initialMouseLocation.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        if selectionInteraction != nil {
            selectionInteraction = nil
            selectionStartRect = nil
            selectionStartPoint = nil
            return
        }

        guard editor.selectedTool == nil else {
            super.mouseUp(with: event)
            return
        }
        initialWindowOrigin = nil
        initialMouseLocation = nil
    }

    private func canvasPoint(for event: NSEvent) -> CGPoint {
        let localPoint = convert(event.locationInWindow, from: nil)
        // NSHostingView is flipped, so its local event coordinates already
        // use SwiftUI's top-left origin. Inverting Y here made vertical
        // selection movement feel backwards while horizontal movement stayed
        // correct.
        return CGPoint(x: localPoint.x, y: localPoint.y)
    }

    private func selectionInteraction(
        at point: CGPoint,
        in rect: CGRect
    ) -> SelectionInteraction? {
        let radius: CGFloat = 14
        let nearLeft = abs(point.x - rect.minX) <= radius
        let nearRight = abs(point.x - rect.maxX) <= radius
        let nearTop = abs(point.y - rect.minY) <= radius
        let nearBottom = abs(point.y - rect.maxY) <= radius

        if nearLeft, nearTop {
            return .resize(.topLeading)
        }
        if nearTop, nearRight {
            return .resize(.topTrailing)
        }
        if nearLeft, nearBottom {
            return .resize(.bottomLeading)
        }
        if nearRight, nearBottom {
            return .resize(.bottomTrailing)
        }
        if nearTop, point.x >= rect.minX, point.x <= rect.maxX {
            return .resize(.top)
        }
        if nearRight, point.y >= rect.minY, point.y <= rect.maxY {
            return .resize(.trailing)
        }
        if nearBottom, point.x >= rect.minX, point.x <= rect.maxX {
            return .resize(.bottom)
        }
        if nearLeft, point.y >= rect.minY, point.y <= rect.maxY {
            return .resize(.leading)
        }
        if rect.contains(point) {
            return .move
        }
        return nil
    }

    private func movedRect(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: bounds.size)
        let x = min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private func resizedRect(
        _ rect: CGRect,
        handle: ResizeHandle,
        by delta: CGSize
    ) -> CGRect {
        let minimum: CGFloat = 24
        let bounds = CGRect(origin: .zero, size: bounds.size)
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeading:
            minX = clamp(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
            minY = clamp(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .top:
            minY = clamp(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .topTrailing:
            maxX = clamp(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
            minY = clamp(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .trailing:
            maxX = clamp(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
        case .bottomTrailing:
            maxX = clamp(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
            maxY = clamp(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .bottom:
            maxY = clamp(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .bottomLeading:
            minX = clamp(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
            maxY = clamp(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .leading:
            minX = clamp(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
