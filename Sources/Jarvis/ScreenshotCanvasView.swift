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
    @FocusState private var textFieldFocused: Bool
    /// 拖动文字时的上一帧位置（`DragGesture` 给的是累计位移）。
    @State private var textDragLocation: CGPoint?

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

            ForEach(editor.annotations) { annotation in
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
                        beginTextEditing(id: id)
                    case .commitOnly:
                        if activeAnnotationID != nil {
                            editor.endMove()
                        }
                    case .beginNew:
                        editor.beginTextEditing(at: start)
                        editor.textDraft = ""
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
        let height = inlineTextEditorHeight
        return ScreenshotInlineTextEditor(
            editor: editor,
            textDraft: $editor.textDraft,
            textFieldFocused: $textFieldFocused,
            fieldWidth: inlineFieldWidth,
            textEditorHeight: height
        )
        // 按住输入区拖动 = 移动这段文字（无论是否已有标注）。
        //
        // 用高优先级手势：拖动被它接走，于是不会变成「框选文字」；而单击（位移小于
        // 3pt）不进这个手势，仍然落到 TextEditor 上完成定位光标与开始输入。
        .highPriorityGesture(
            // 坐标系必须钉在画布上：手势挂在输入区上，而输入区本身会跟着移动，
            // 用它自己的局部坐标算位移会自我反馈、抖起来。
            DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.canvasCoordinateSpace))
                .onChanged { value in
                    let previous = textDragLocation ?? value.startLocation
                    let delta = CGPoint(
                        x: value.location.x - previous.x,
                        y: value.location.y - previous.y
                    )
                    textDragLocation = value.location
                    guard delta != .zero else { return }
                    editor.moveTextEditing(by: delta)
                }
                .onEnded { _ in textDragLocation = nil }
        )
        // 输入区跟着光标走，并夹在画布内：它原来是靠 .position 定位的，重做控件时
        // 被连着参数一起删掉了，于是光标跑到了画布左上角。
        .position(
            x: point.x - 8 + inlineFieldWidth / 2,
            y: min(
                max(point.y + height / 2, height / 2),
                max(height / 2, editor.canvasSize.height - height / 2)
            )
        )
    }

    /// 正在输入的话先把草稿落到标注上。编辑器没有确认按钮，这些「离开输入」的
    /// 动作就是提交时机。
    private func commitTextIfEditing() {
        guard editor.isEditingText else { return }
        commitText()
    }

    private func beginTextEditing(id: UUID) {
        guard let annotation = editor.annotations.first(where: { $0.id == id && $0.kind == .text }) else { return }
        editor.textInputAnchor = CGPoint(
            x: annotation.start.x - annotation.textSize.width / 2 + 9,
            y: annotation.start.y
        )
        editor.editingTextID = id
        editor.textDraft = annotation.text ?? ""
        editor.textFontSize = annotation.fontSize
        editor.textColor = annotation.textColor
        editor.textBold = annotation.isBold
        editor.textItalic = annotation.isItalic
        editor.textStrikethrough = annotation.isStrikethrough
        textFieldFocused = true
    }

    private func commitText() {
        editor.commitTextEditing()
        textFieldFocused = false
    }

    private func cancelText() {
        editor.endTextEditing()
        textFieldFocused = false
    }

    /// 输入区的宽度：跟着内容长，上限留到画布边。
    ///
    /// 原来卡在「十五个字符」宽（还带一圈胶囊底），既像输入框又逼着文字提前折行。
    private var inlineFieldWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: inlineTextFont]
        let measuredWidth = inlineTextLines
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let minimumFieldWidth = textWidth(for: 6, using: attributes) + 30
        let availableWidth = max(minimumFieldWidth, editor.canvasSize.width - inlineFieldHorizontalMargin)
        let contentWidth = measuredWidth + 30
        return min(availableWidth, max(minimumFieldWidth, contentWidth))
    }

    /// 输入区的高度：按实际行数长（换行靠回车，不靠自动折行）。
    private var inlineTextEditorHeight: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: inlineTextFont]
        let width = max(inlineFieldWidth - 30, 1)
        let totalLines = inlineTextLineCount(using: attributes, width: width)
        let lineHeight = max(
            editor.textFontSize * 1.28,
            inlineTextFont.ascender - inlineTextFont.descender + inlineTextFont.leading
        )
        // 不封顶：内容多高输入区就多高，这样它永远不需要滚动，滚动条也就不会出现。
        // 多出来的 16pt 是给 TextEditor 自己的内容内边距留的余量。
        return max(lineHeight + 16, CGFloat(totalLines) * lineHeight + 16)
    }

    private var inlineFieldHorizontalMargin: CGFloat {
        96
    }

    private func inlineTextLineCount(
        using attributes: [NSAttributedString.Key: Any],
        width: CGFloat
    ) -> Int {
        inlineTextLines.reduce(0) { count, line in
            count + wrappedLines(for: line, width: width, using: attributes).count
        }
    }

    private func wrappedLines(
        for line: String,
        width: CGFloat,
        using attributes: [NSAttributedString.Key: Any]
    ) -> [String] {
        guard !line.isEmpty else { return [""] }

        var lines: [String] = []
        var currentLine = ""
        var currentWidth: CGFloat = 0

        for character in line {
            let characterString = String(character)
            let characterWidth = (characterString as NSString).size(withAttributes: attributes).width
            if !currentLine.isEmpty, currentWidth + characterWidth > width {
                lines.append(currentLine)
                currentLine = characterString
                currentWidth = characterWidth
            } else if currentLine.count >= 15 {
                lines.append(currentLine)
                currentLine = characterString
                currentWidth = characterWidth
            } else {
                currentLine.append(character)
                currentWidth += characterWidth
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
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

    private var inlineTextLines: [String] {
        editor.textDraft.components(separatedBy: "\n")
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

private struct ScreenshotInlineTextEditor: View {
    @ObservedObject var editor: ScreenshotEditorModel
    @Binding var textDraft: String
    @FocusState.Binding var textFieldFocused: Bool
    let fieldWidth: CGFloat
    let textEditorHeight: CGFloat

    var body: some View {
        // 只留光标和文字：没有输入框外观、没有确认/取消按钮。
        //
        // 底下仍然是一个真的 TextEditor——它承担输入法、光标位置、选区这些必须由
        // 系统控件负责的事，只是不带任何装饰。文字与光标的位置由它的内边距决定，
        // 那圈内边距和落盘时 `addText(alignedAtLeft:)` / 渲染端的 ±9 是配套的，
        // 去掉就会让「正在输入的文字」和「提交后的文字」错位。
        TextEditor(text: $textDraft)
            .scrollContentBackground(.hidden)
            .font(.system(size: editor.textFontSize, weight: editor.textBold ? .semibold : .regular))
            .italic(editor.textItalic)
            .strikethrough(editor.textStrikethrough, color: editor.textColor.color)
            .foregroundStyle(editor.textColor.color)
            .tint(editor.textColor.color)
            .focused($textFieldFocused)
            .scrollIndicators(.hidden, axes: .vertical)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .frame(width: fieldWidth, height: textEditorHeight)
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
