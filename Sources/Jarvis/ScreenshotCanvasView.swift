import AppKit
import SwiftUI

struct ScreenshotCanvasView: View {
    let image: NSImage
    @ObservedObject var editor: ScreenshotEditorModel
    let interactive: Bool
    let showsSelectionOverlay: Bool

    init(
        image: NSImage,
        editor: ScreenshotEditorModel,
        interactive: Bool,
        showsSelectionOverlay: Bool = true
    ) {
        self.image = image
        self.editor = editor
        self.interactive = interactive
        self.showsSelectionOverlay = showsSelectionOverlay
    }

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var lastDragLocation: CGPoint?
    @State private var mosaicPoints: [CGPoint] = []
    @State private var activeAnnotationID: UUID?
    @State private var textInputPoint: CGPoint?
    @State private var editingTextID: UUID?
    @State private var textDraft = ""
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: editor.originalImage)
                .resizable()
                .interpolation(.high)
                .frame(width: editor.canvasSize.width, height: editor.canvasSize.height)

            ForEach(editor.annotations) { annotation in
                ScreenshotAnnotationView(
                    annotation: annotation,
                    canvasSize: editor.canvasSize,
                    mosaicImage: editor.mosaicImage(style: annotation.mosaicStyle)
                )
            }

            if let draftAnnotation {
                ScreenshotAnnotationView(
                    annotation: draftAnnotation,
                    canvasSize: editor.canvasSize,
                    mosaicImage: editor.mosaicImage(style: draftAnnotation.mosaicStyle),
                    isDraft: true
                )
            }

            if interactive {
                if editor.selectedTool != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(canvasGesture)
                }

                if let textInputPoint {
                    inlineTextEditor(at: textInputPoint)
                }
            }
        }
        .frame(width: editor.canvasSize.width, height: editor.canvasSize.height)
        .overlay {
            if interactive, showsSelectionOverlay {
                if editor.selectionRect != nil {
                    ScreenshotSelectionOverlay(editor: editor)
                } else {
                    Rectangle()
                        .stroke(Color.blue.opacity(0.48), lineWidth: 1)
                }
            }
        }
    }

    private var canvasGesture: some Gesture {
        DragGesture(minimumDistance: editor.selectedTool == .text ? 0 : 2)
            .onChanged { value in
                if dragStart == nil {
                    guard let start = editablePoint(value.startLocation) else { return }
                    dragStart = start
                    dragCurrent = editablePoint(value.location) ?? start
                    lastDragLocation = dragCurrent

                    if editor.selectedTool == .text {
                        activeAnnotationID = editor.textAnnotation(at: start)
                        editor.selectedAnnotationID = activeAnnotationID
                        if let activeAnnotationID {
                            editor.beginMove(id: activeAnnotationID)
                        }
                    } else {
                        editor.clearSelection()
                    }
                }

                guard let dragStart else { return }
                let currentPoint = editablePoint(value.location) ?? dragStart
                if let activeAnnotationID,
                   editor.selectedTool == .text,
                   let lastDragLocation
                {
                    editor.moveAnnotation(
                        id: activeAnnotationID,
                        by: CGPoint(
                            x: currentPoint.x - lastDragLocation.x,
                            y: currentPoint.y - lastDragLocation.y
                        ),
                        within: editor.editingRect
                    )
                    self.lastDragLocation = currentPoint
                } else if editor.selectedTool == .mosaic,
                          editor.mosaicMode == .brush
                {
                    if mosaicPoints.last.map({ distance(from: $0, to: currentPoint) > 2 }) ?? true {
                        mosaicPoints.append(currentPoint)
                    }
                    dragCurrent = currentPoint
                } else {
                    dragCurrent = currentPoint
                }
            }
            .onEnded { value in
                guard let start = dragStart else {
                    resetDragState()
                    return
                }
                let end = editablePoint(value.location) ?? start
                let dragDistance = distance(from: start, to: end)
                guard let selectedTool = editor.selectedTool else {
                    resetDragState()
                    return
                }

                switch selectedTool {
                case .arrow:
                    editor.addArrow(from: start, to: end)
                case .mosaic:
                    let points = editor.mosaicMode == .brush
                        ? (mosaicPoints.count > 1 ? mosaicPoints : [start, end])
                        : [start, end]
                    editor.addMosaic(points: points)
                case .text:
                    if let activeAnnotationID {
                        editor.endMove()
                        if dragDistance < 8 {
                            beginTextEditing(id: activeAnnotationID)
                        }
                    } else if dragDistance < 8 {
                        textInputPoint = start
                        editingTextID = nil
                        textDraft = ""
                        textFieldFocused = true
                    }
                }
                resetDragState()
            }
    }

    private func editablePoint(_ point: CGPoint) -> CGPoint? {
        guard let selectionRect = editor.selectionRect else { return point }
        guard selectionRect.insetBy(dx: -1, dy: -1).contains(point) else { return nil }
        return CGPoint(
            x: min(max(point.x, selectionRect.minX), selectionRect.maxX),
            y: min(max(point.y, selectionRect.minY), selectionRect.maxY)
        )
    }

    private var draftAnnotation: ScreenshotAnnotation? {
        guard let start = dragStart, let end = dragCurrent else { return nil }
        guard let selectedTool = editor.selectedTool else { return nil }
        switch selectedTool {
        case .text:
            return nil
        case .arrow:
            return .init(
                kind: .arrow,
                points: [start, end],
                text: nil,
                brushSize: editor.arrowLineWidth,
                color: editor.arrowColor,
                lineWidth: editor.arrowLineWidth,
                arrowHeadSize: editor.arrowHeadSize,
                arrowHeadStyle: editor.arrowHeadStyle
            )
        case .mosaic:
            let points = editor.mosaicMode == .brush ? mosaicPoints : [start, end]
            return .init(
                kind: .mosaic,
                points: points,
                text: nil,
                brushSize: editor.mosaicBrushSize,
                mosaicMode: editor.mosaicMode,
                mosaicStyle: editor.mosaicStyle
            )
        }
    }

    private func inlineTextEditor(at point: CGPoint) -> some View {
        ScreenshotInlineTextEditor(
            editor: editor,
            textDraft: $textDraft,
            textFieldFocused: $textFieldFocused,
            point: point,
            fieldWidth: inlineFieldWidth,
            editorWidth: inlineEditorWidth,
            editorHeight: inlineEditorHeight,
            textEditorHeight: inlineTextEditorHeight,
            onCommit: commitText,
            onCancel: cancelText
        )
    }

    private func beginTextEditing(id: UUID) {
        guard let annotation = editor.annotations.first(where: { $0.id == id && $0.kind == .text }) else { return }
        textInputPoint = annotation.start
        editingTextID = id
        textDraft = annotation.text ?? ""
        editor.textFontSize = annotation.fontSize
        editor.textColor = annotation.textColor
        editor.textBold = annotation.isBold
        editor.textItalic = annotation.isItalic
        editor.textStrikethrough = annotation.isStrikethrough
        textFieldFocused = true
    }

    private func commitText() {
        guard let textInputPoint else { return }
        if let editingTextID {
            editor.updateText(id: editingTextID, text: textDraft)
        } else {
            editor.addText(at: textInputPoint, text: textDraft)
        }
        self.textInputPoint = nil
        editingTextID = nil
        textDraft = ""
        textFieldFocused = false
    }

    private func cancelText() {
        textInputPoint = nil
        editingTextID = nil
        textDraft = ""
        textFieldFocused = false
    }

    private var inlineFieldWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: inlineTextFont]
        let measuredWidth = inlineTextLines
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let availableWidth = max(190, editor.canvasSize.width - 70)
        return min(availableWidth, max(190, measuredWidth + 30))
    }

    private var inlineTextEditorHeight: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: inlineTextFont]
        let width = max(inlineFieldWidth - 12, 1)
        let totalLines = inlineTextLines.reduce(0) { count, line in
            let measuredWidth = (line as NSString).size(withAttributes: attributes).width
            return count + max(1, Int(ceil(measuredWidth / width)))
        }
        let lineHeight = max(editor.textFontSize * 1.28, inlineTextFont.ascender - inlineTextFont.descender)
        return max(38, CGFloat(totalLines) * lineHeight + 8)
    }

    private var inlineTextFont: NSFont {
        NSFont.systemFont(
            ofSize: editor.textFontSize,
            weight: editor.textBold ? .semibold : .regular
        )
    }

    private var inlineTextLines: [String] {
        textDraft.components(separatedBy: "\n")
    }

    private var inlineEditorWidth: CGFloat {
        inlineFieldWidth + 50
    }

    private var inlineEditorHeight: CGFloat {
        max(42, inlineTextEditorHeight + 10)
    }

    private func resetDragState() {
        dragStart = nil
        dragCurrent = nil
        lastDragLocation = nil
        mosaicPoints.removeAll()
        activeAnnotationID = nil
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

private struct ScreenshotInlineTextEditor: View {
    @ObservedObject var editor: ScreenshotEditorModel
    @Binding var textDraft: String
    @FocusState.Binding var textFieldFocused: Bool
    let point: CGPoint
    let fieldWidth: CGFloat
    let editorWidth: CGFloat
    let editorHeight: CGFloat
    let textEditorHeight: CGFloat
    let onCommit: () -> Void
    let onCancel: () -> Void

    private var editorField: some View {
        TextEditor(text: $textDraft)
            .scrollContentBackground(.hidden)
            .font(.system(size: editor.textFontSize, weight: editor.textBold ? .semibold : .regular))
            .italic(editor.textItalic)
            .strikethrough(editor.textStrikethrough, color: editor.textColor.color)
            .foregroundStyle(editor.textColor.color)
            .tint(editor.textColor.color)
            .focused($textFieldFocused)
            .frame(width: fieldWidth, height: textEditorHeight)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
    }

    private var actionButtons: some View {
        VStack(spacing: 5) {
            Button(action: onCommit) {
                Image(systemName: "checkmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.jarvisCyan)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black.opacity(0.56))
        }
        .font(.system(size: max(12, editor.textFontSize * 0.58), weight: .medium))
    }

    var body: some View {
        HStack(spacing: 6) {
            editorField
            actionButtons
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: editorWidth, height: editorHeight)
        .background(Color.white.opacity(0.82))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
        .position(
            x: min(
                max(point.x + editorWidth / 2, editorWidth / 2),
                max(editorWidth / 2, editor.canvasSize.width - editorWidth / 2)
            ),
            y: min(
                max(point.y + editorHeight / 2, editorHeight / 2),
                max(editorHeight / 2, editor.canvasSize.height - editorHeight / 2)
            )
        )
        .onAppear {
            DispatchQueue.main.async {
                textFieldFocused = true
            }
        }
    }
}

private struct ScreenshotSelectionOverlay: View {
    @ObservedObject var editor: ScreenshotEditorModel
    @State private var moveStartRect: CGRect?
    @State private var resizeStartRect: CGRect?

    private enum SelectionHandle: CaseIterable, Hashable {
        case topLeading
        case top
        case topTrailing
        case trailing
        case bottomTrailing
        case bottom
        case bottomLeading
        case leading
    }

    var body: some View {
        if let selectionRect = editor.selectionRect {
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: editor.canvasSize))
                    path.addRect(selectionRect)
                }
                .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Path { path in
                    path.addRect(selectionRect)
                }
                .stroke(Color.blue.opacity(0.96), lineWidth: 2)
                .allowsHitTesting(false)

                Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .position(
                        x: min(
                            max(selectionRect.minX + 42, 42),
                            editor.canvasSize.width - 42
                        ),
                        y: max(16, selectionRect.minY - 16)
                    )
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .gesture(moveGesture)
                    .allowsHitTesting(editor.selectedTool == nil)

                ForEach(SelectionHandle.allCases, id: \.self) { handle in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(Color.blue, lineWidth: 2)
                        }
                        .position(handlePoint(handle, in: selectionRect))
                        .contentShape(Circle())
                        .gesture(resizeGesture(handle))
                        .allowsHitTesting(editor.selectedTool == nil)
                }
            }
            .frame(width: editor.canvasSize.width, height: editor.canvasSize.height)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let selectionRect = editor.selectionRect else { return }
                if moveStartRect == nil {
                    moveStartRect = selectionRect
                }
                guard let moveStartRect else { return }
                editor.updateSelectionRect(clampedMove(moveStartRect, by: value.translation))
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }

    private func resizeGesture(_ handle: SelectionHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let selectionRect = editor.selectionRect else { return }
                if resizeStartRect == nil {
                    resizeStartRect = selectionRect
                }
                guard let resizeStartRect else { return }
                editor.updateSelectionRect(resizedRect(resizeStartRect, handle: handle, by: value.translation))
            }
            .onEnded { _ in
                resizeStartRect = nil
            }
    }

    private func clampedMove(_ rect: CGRect, by delta: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: editor.canvasSize)
        let x = min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private func resizedRect(
        _ rect: CGRect,
        handle: SelectionHandle,
        by delta: CGSize
    ) -> CGRect {
        let minimum: CGFloat = 24
        let bounds = CGRect(origin: .zero, size: editor.canvasSize)
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY

        switch handle {
        case .topLeading:
            minX = clamped(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
            minY = clamped(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .top:
            minY = clamped(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .topTrailing:
            maxX = clamped(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
            minY = clamped(rect.minY + delta.height, lower: bounds.minY, upper: rect.maxY - minimum)
        case .trailing:
            maxX = clamped(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
        case .bottomTrailing:
            maxX = clamped(rect.maxX + delta.width, lower: rect.minX + minimum, upper: bounds.maxX)
            maxY = clamped(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .bottom:
            maxY = clamped(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .bottomLeading:
            minX = clamped(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
            maxY = clamped(rect.maxY + delta.height, lower: rect.minY + minimum, upper: bounds.maxY)
        case .leading:
            minX = clamped(rect.minX + delta.width, lower: bounds.minX, upper: rect.maxX - minimum)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func handlePoint(_ handle: SelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
        case .trailing: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
        case .leading: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
