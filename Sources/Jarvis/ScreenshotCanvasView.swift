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

    static let canvasCoordinateSpace = "jarvis.screenshot.canvas"

    /// 文字工具下的一次点击该做什么。
    ///
    /// 单独抽出来是因为「确认的那一下不再开新输入」这条规则只靠肉眼盯视图代码很容易
    /// 漏掉（这条流程已经漏过一次），而且漏掉的表现是「一点就新开一个编辑、刚打的草稿
    /// 还没了」。
    enum TextToolTapOutcome: Equatable {
        /// 先提交，然后开始编辑这段已有的文字。
        case commitThenEditExisting(UUID)
        /// 只提交（点到输入区以外，用来确认）。
        case commitOnly
        /// 开始一段新的文字。
        case beginNew
    }

    /// 从既有标注反推出输入锚点（`textCenter(alignedAtLeft:)` 的逆运算）。
    ///
    /// 位置公式住在 `ScreenshotAnnotationText.topLeft(of:)`——预览、输入控件、导出
    /// 都用那一份，这里只是它在画布视图里的名字。
    static func textEditingAnchor(for annotation: ScreenshotAnnotation) -> CGPoint {
        ScreenshotAnnotationText.topLeft(of: annotation)
    }

    static func textToolTapOutcome(
        isEditing: Bool,
        existingAnnotationID: UUID?,
        dragDistance: CGFloat
    ) -> TextToolTapOutcome {
        let isTap = dragDistance < 8
        if let existingAnnotationID {
            return isTap ? .commitThenEditExisting(existingAnnotationID) : .commitOnly
        }
        // 正在编辑时的那一下点击是「确认」，不该顺手在同一处再开一段。
        return isTap && !isEditing ? .beginNew : .commitOnly
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(nsImage: editor.originalImage)
                .resizable()
                .interpolation(.high)
                .frame(width: editor.canvasSize.width, height: editor.canvasSize.height)

            ForEach(editor.renderedTranslationBlocks) { block in
                ScreenshotTranslationBlockView(block: block)
            }

            ForEach(canvasAnnotations) { annotation in
                ScreenshotAnnotationView(
                    annotation: annotation,
                    canvasSize: editor.canvasSize,
                    // 只有马赛克需要过滤图。原来对每个标注都取一次，于是画下第一条
                    // 箭头就会触发整幅 6K 的高斯模糊——新建 CIContext、过滤、把 81MB
                    // 位图读回，全在主线程上。
                    mosaicImage: annotation.kind == .mosaic
                        ? editor.mosaicImage(style: annotation.mosaicStyle)
                        : nil
                )
                // 删除/复制原来只有键盘路径（⌫ / ⌘D），界面上没有任何提示，等于
                // 没做。标注视图自身关掉了命中测试（它们是覆盖全画布的图层），所以
                // 菜单要挂在一块按标注外接矩形单独铺出来、可接收点击的区域上。
                .overlay {
                    let bounds = annotation.canvasBounds
                    Color.clear
                        .frame(width: max(bounds.width, 1), height: max(bounds.height, 1))
                        .contentShape(Rectangle())
                        .position(x: bounds.midX, y: bounds.midY)
                        .contextMenu {
                            Button("复制标注") {
                                editor.selectedAnnotationID = annotation.id
                                editor.duplicateSelectedAnnotation()
                            }
                            Button("删除标注", role: .destructive) {
                                editor.deleteAnnotation(id: annotation.id)
                            }
                        }
                }
            }

            if let draftAnnotation {
                ScreenshotAnnotationView(
                    annotation: draftAnnotation,
                    canvasSize: editor.canvasSize,
                    mosaicImage: draftAnnotation.kind == .mosaic
                        ? editor.mosaicImage(style: draftAnnotation.mosaicStyle)
                        : nil,
                    isDraft: true
                )
            }

            if interactive {
                if editor.selectedTool != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(canvasGesture)
                }

                if let textInputAnchor = editor.textInputAnchor {
                    inlineTextEditor(at: textInputAnchor)
                }
            }
        }
        .frame(width: editor.canvasSize.width, height: editor.canvasSize.height)
        .coordinateSpace(name: Self.canvasCoordinateSpace)
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
                case .rectangle:
                    editor.addRectangle(from: start, to: end)
                case .mosaic:
                    let points = editor.mosaicMode == .brush
                        ? (mosaicPoints.count > 1 ? mosaicPoints : [start, end])
                        : [start, end]
                    editor.addMosaic(points: points)
                case .text:
                    // 点击输入区以外 = 确认（先把草稿落下去）；具体该做什么见
                    // `textToolTapOutcome`。
                    let outcome = Self.textToolTapOutcome(
                        isEditing: editor.isEditingText,
                        existingAnnotationID: activeAnnotationID,
                        dragDistance: dragDistance
                    )
                    commitTextIfEditing()
                    switch outcome {
                    case let .commitThenEditExisting(id):
                        editor.endMove()
                        editor.beginTextEditing(id: id)
                    case .commitOnly:
                        if activeAnnotationID != nil {
                            editor.endMove()
                        }
                    case .beginNew:
                        editor.beginTextEditing(at: start)
                        editor.textDraft = ""
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

    /// 画布上真正要画的标注：正在编辑的那段文字除外。
    ///
    /// 它是画布上唯一「有另一份正在显示」的标注——内联输入控件正把同样的文字摆在
    /// 同一个位置。两处都画，就是两份叠着的字（二次编辑时最容易看见：点一下已写好的
    /// 文字，它就重影）。输入控件本来就是最终要落下去的那份显示的化身，让位给它。
    ///
    /// 例外是多行文字：输入控件是单行的（回车即确认），顶上去只显示得了第一行，
    /// 第 2..n 行会在编辑期间凭空消失。这种文字现在的界面打不出来（只可能来自旧
    /// 数据），那就让画布继续画着，别在半路抽走几行。
    var canvasAnnotations: [ScreenshotAnnotation] {
        guard let editingTextID = editor.editingTextID, editor.isEditingText else {
            return editor.annotations
        }
        let editedIsMultiLine = editor.annotations
            .first { $0.id == editingTextID }?
            .text?
            .contains("\n") ?? false
        guard !editedIsMultiLine else { return editor.annotations }
        return editor.annotations.filter { $0.id != editingTextID }
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
        case .rectangle:
            return .init(
                kind: .rectangle,
                points: [start, end],
                text: nil,
                brushSize: editor.rectangleLineWidth,
                color: editor.rectangleColor,
                lineWidth: editor.rectangleLineWidth,
                lineStyle: editor.rectangleLineStyle
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
        // 视图原点 = 锚点 = 确认后文字的左上角。输入控件把内边距归零了，所以光标
        // 停的位置就是文字将要落下的位置。
        ScreenshotSingleLineTextInput(
            text: $editor.textDraft,
            fontSize: editor.textFontSize,
            isBold: editor.textBold,
            isItalic: editor.textItalic,
            isStrikethrough: editor.textStrikethrough,
            color: editor.textColor.nsColor,
            onCommit: { commitText() },
            onMove: { delta in editor.moveTextEditing(by: delta) }
        )
        .frame(width: inlineFieldWidth, height: inlineTextEditorHeight)
        .offset(x: point.x, y: point.y)
    }

    /// 正在输入的话先把草稿落到标注上。编辑器没有确认按钮，这些「离开输入」的
    /// 动作就是提交时机。
    private func commitTextIfEditing() {
        guard editor.isEditingText else { return }
        commitText()
    }

    private func commitText() {
        editor.commitTextEditing()
    }

    private func cancelText() {
        editor.endTextEditing()
    }

    /// 输入区的宽度：跟着内容长，上限留到画布边。
    private var inlineFieldWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: inlineTextFont]
        let measuredWidth = (editor.textDraft as NSString).size(withAttributes: attributes).width
        let minimumFieldWidth = textWidth(for: 6, using: attributes) + 8
        let availableWidth = max(minimumFieldWidth, editor.canvasSize.width - inlineFieldHorizontalMargin)
        return min(availableWidth, max(minimumFieldWidth, measuredWidth + 8))
    }

    /// 单行输入区的高度：正好一行。
    private var inlineTextEditorHeight: CGFloat {
        max(
            editor.textFontSize * 1.28,
            inlineTextFont.ascender - inlineTextFont.descender + inlineTextFont.leading
        )
    }

    private var inlineFieldHorizontalMargin: CGFloat {
        96
    }

    private func textWidth(
        for characterCount: Int,
        using attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let sample = String(repeating: "中", count: characterCount)
        return (sample as NSString).size(withAttributes: attributes).width
    }

    private var inlineTextFont: NSFont {
        NSFont.systemFont(
            ofSize: editor.textFontSize,
            weight: editor.textBold ? .semibold : .regular
        )
    }

    private var inlineEditorWidth: CGFloat {
        inlineFieldWidth + 96
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
                    .font(JarvisTypography.monospaced)
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
