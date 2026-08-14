import AppKit
import CoreImage
import SwiftUI

enum ScreenshotTextColor: String, CaseIterable, Identifiable, Equatable {
    case red
    case yellow
    case white
    case black
    case cyan
    case blue
    case green

    var id: String {
        rawValue
    }

    var color: Color {
        switch self {
        case .red: Color(red: 1, green: 0.12, blue: 0.12)
        case .yellow: .yellow
        case .white: .white
        case .black: .black
        case .cyan: .cyan
        case .blue: Color(red: 0.1, green: 0.38, blue: 0.95)
        case .green: Color(red: 0.12, green: 0.62, blue: 0.25)
        }
    }
}

enum ScreenshotMosaicMode: String, CaseIterable, Identifiable, Equatable {
    case brush
    case rectangle

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .brush: "涂抹"
        case .rectangle: "框选"
        }
    }

    var icon: String {
        switch self {
        case .brush: "scribble.variable"
        case .rectangle: "rectangle.dashed"
        }
    }
}

enum ScreenshotMosaicStyle: String, CaseIterable, Identifiable, Equatable {
    case pixelate
    case blur

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pixelate: "像素化"
        case .blur: "模糊"
        }
    }

    var icon: String {
        switch self {
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
        }
    }
}

enum ScreenshotArrowHeadStyle: String, CaseIterable, Identifiable, Equatable {
    case filled
    case none

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .filled: "箭头"
        case .none: "直线"
        }
    }
}

struct ScreenshotAnnotation: Identifiable, Equatable {
    enum Kind: Equatable {
        case arrow
        case mosaic
        case text
    }

    var id = UUID()
    let kind: Kind
    var points: [CGPoint]
    var text: String?
    var brushSize: CGFloat
    var color: ScreenshotTextColor = .red
    var lineWidth: CGFloat = 5
    var arrowHeadSize: CGFloat = 20
    var arrowHeadStyle: ScreenshotArrowHeadStyle = .filled
    var fontSize: CGFloat = 22
    var textColor: ScreenshotTextColor = .red
    var isBold = true
    var isItalic = false
    var isStrikethrough = false
    var mosaicMode: ScreenshotMosaicMode = .rectangle
    var mosaicStyle: ScreenshotMosaicStyle = .blur

    var start: CGPoint {
        points.first ?? .zero
    }

    var end: CGPoint {
        points.last ?? start
    }

    var rect: CGRect {
        CGRect(
            x: points.map(\.x).min() ?? 0,
            y: points.map(\.y).min() ?? 0,
            width: (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0),
            height: (points.map(\.y).max() ?? 0) - (points.map(\.y).min() ?? 0)
        )
    }

    var textSize: CGSize {
        let lines = (text ?? "").components(separatedBy: "\n")
        let font = NSFont.systemFont(
            ofSize: fontSize,
            weight: isBold ? .semibold : .regular
        )
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let lineWidths = lines.map { ($0 as NSString).size(withAttributes: attributes).width }
        let lineHeight = max(fontSize * 1.22, font.ascender - font.descender + font.leading)
        let width = max(90, (lineWidths.max() ?? 0) + 18)
        let height = max(lineHeight + 14, lineHeight * CGFloat(max(lines.count, 1)) + 10)
        return CGSize(width: width, height: height)
    }

    var bounds: CGRect {
        switch kind {
        case .arrow:
            let padding = max(lineWidth, arrowHeadSize * 0.22) + 8
            return rect.insetBy(dx: -padding, dy: -padding)
        case .mosaic:
            let padding = mosaicMode == .brush ? brushSize / 2 + 4 : 4
            return rect.insetBy(dx: -padding, dy: -padding)
        case .text:
            let size = textSize
            return CGRect(
                x: start.x - size.width / 2,
                y: start.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }
}

@MainActor
final class ScreenshotEditorModel: ObservableObject {
    @Published private(set) var originalImage: NSImage
    private(set) var originalData: Data
    private(set) var originalOutputData: Data
    let canvasSize: CGSize
    private var blurredImageCache: NSImage?
    private var pixelatedImageCache: NSImage?

    @Published var selectedTool: ScreenshotTool?
    @Published var selectedAnnotationID: UUID?
    @Published private(set) var selectionRect: CGRect?
    @Published var mosaicBrushSize: CGFloat = 28
    @Published var mosaicMode: ScreenshotMosaicMode = .rectangle
    @Published var mosaicStyle: ScreenshotMosaicStyle = .blur
    @Published var arrowColor: ScreenshotTextColor = .red
    @Published var arrowLineWidth: CGFloat = 5
    @Published var arrowHeadSize: CGFloat = 20
    @Published var arrowHeadStyle: ScreenshotArrowHeadStyle = .filled
    @Published var textFontSize: CGFloat = 22
    @Published var textColor: ScreenshotTextColor = .red
    @Published var textBold = true
    @Published var textItalic = false
    @Published var textStrikethrough = false
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published private(set) var redoStack: [[ScreenshotAnnotation]] = []

    private let coordinateSpace: ScreenshotCoordinateSpace
    private let initialSelectionRect: CGRect?
    private var undoStack: [[ScreenshotAnnotation]] = []
    private var activeMoveSnapshot: [ScreenshotAnnotation]?

    init(
        image: NSImage,
        data: Data,
        outputData: Data,
        canvasSize: CGSize,
        outputRect: CGRect? = nil
    ) {
        originalImage = image
        originalData = data
        self.canvasSize = canvasSize
        originalOutputData = outputData
        coordinateSpace = ScreenshotCoordinateSpace(
            screenFrame: CGRect(origin: .zero, size: canvasSize),
            canvasSize: canvasSize
        )
        let canvasSelectionRect: CGRect? = if let outputRect {
            coordinateSpace.canvasRect(fromOutputRect: outputRect)
        } else {
            nil
        }
        selectionRect = canvasSelectionRect
        initialSelectionRect = canvasSelectionRect
        blurredImageCache = nil
        pixelatedImageCache = nil
    }

    /// AppKit's screen coordinates use a bottom-left origin while SwiftUI's
    /// canvas uses a top-left origin. Keep the export rect in AppKit space and
    /// expose a canvas-space rect for the editing overlay and gestures.
    var editingRect: CGRect? {
        selectionRect
    }

    var outputRect: CGRect? {
        guard let selectionRect else { return nil }
        return coordinateSpace.outputRect(fromCanvasRect: selectionRect)
    }

    func updateSelectionRect(_ rect: CGRect) {
        guard let clamped = coordinateSpace.clampedCanvasRect(rect) else { return }
        guard clamped != selectionRect else { return }
        selectionRect = clamped
    }

    func selectionFrame(on screenFrame: CGRect) -> CGRect? {
        guard let outputRect else { return nil }
        return ScreenshotCoordinateSpace(
            screenFrame: screenFrame,
            canvasSize: canvasSize
        ).screenRect(fromOutputRect: outputRect)
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var canRedo: Bool {
        !redoStack.isEmpty
    }

    var secondaryBarVisible: Bool {
        selectedTool == .arrow || selectedTool == .mosaic || selectedTool == .text
    }

    var selectedAnnotation: ScreenshotAnnotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first { $0.id == selectedAnnotationID }
    }

    func selectTool(_ tool: ScreenshotTool?) {
        selectedTool = tool
        if tool != .text {
            selectedAnnotationID = nil
        }
    }

    func addArrow(from start: CGPoint, to end: CGPoint) {
        guard distance(from: start, to: end) > 8 else { return }
        append(.init(
            kind: .arrow,
            points: [start, end],
            text: nil,
            brushSize: arrowLineWidth,
            color: arrowColor,
            lineWidth: arrowLineWidth,
            arrowHeadSize: arrowHeadSize,
            arrowHeadStyle: arrowHeadStyle
        ))
    }

    func addMosaic(points: [CGPoint]) {
        guard points.count > 1 else { return }
        append(.init(
            kind: .mosaic,
            points: points,
            text: nil,
            brushSize: mosaicBrushSize,
            mosaicMode: mosaicMode,
            mosaicStyle: mosaicStyle
        ))
    }

    func addText(at point: CGPoint, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        append(.init(
            kind: .text,
            points: [point],
            text: text,
            brushSize: 0,
            fontSize: textFontSize,
            textColor: textColor,
            isBold: textBold,
            isItalic: textItalic,
            isStrikethrough: textStrikethrough
        ))
    }

    func beginMove(id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        selectedAnnotationID = id
        activeMoveSnapshot = annotations
    }

    func moveAnnotation(id: UUID, by delta: CGPoint, within constraint: CGRect? = nil) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        var adjustedDelta = delta
        if let constraint {
            let bounds = annotations[index].bounds
            if bounds.minX + adjustedDelta.x < constraint.minX {
                adjustedDelta.x += constraint.minX - (bounds.minX + adjustedDelta.x)
            }
            if bounds.maxX + adjustedDelta.x > constraint.maxX {
                adjustedDelta.x -= (bounds.maxX + adjustedDelta.x) - constraint.maxX
            }
            if bounds.minY + adjustedDelta.y < constraint.minY {
                adjustedDelta.y += constraint.minY - (bounds.minY + adjustedDelta.y)
            }
            if bounds.maxY + adjustedDelta.y > constraint.maxY {
                adjustedDelta.y -= (bounds.maxY + adjustedDelta.y) - constraint.maxY
            }
        }
        annotations[index].points = annotations[index].points.map {
            CGPoint(x: $0.x + adjustedDelta.x, y: $0.y + adjustedDelta.y)
        }
    }

    func endMove() {
        guard let snapshot = activeMoveSnapshot else { return }
        activeMoveSnapshot = nil
        guard snapshot != annotations else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    func textAnnotation(at point: CGPoint) -> UUID? {
        annotations.reversed().first { annotation in
            annotation.kind == .text
                && annotation.bounds.insetBy(dx: -8, dy: -8).contains(point)
        }?.id
    }

    func updateText(id: UUID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id && $0.kind == .text }) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            deleteAnnotation(id: id)
            return
        }
        var updated = annotations[index]
        updated.text = text
        updated.fontSize = textFontSize
        updated.textColor = textColor
        updated.isBold = textBold
        updated.isItalic = textItalic
        updated.isStrikethrough = textStrikethrough
        guard updated != annotations[index] else { return }
        recordBeforeMutation()
        annotations[index] = updated
        redoStack.removeAll()
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }
        deleteAnnotation(id: selectedAnnotationID)
    }

    func deleteAnnotation(id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        recordBeforeMutation()
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }
        redoStack.removeAll()
    }

    func duplicateSelectedAnnotation() {
        guard let selectedAnnotationID,
              var copy = annotations.first(where: { $0.id == selectedAnnotationID }) else { return }
        recordBeforeMutation()
        copy.id = UUID()
        copy.points = copy.points.map { CGPoint(x: $0.x + 16, y: $0.y + 16) }
        annotations.append(copy)
        self.selectedAnnotationID = copy.id
        redoStack.removeAll()
    }

    func clearSelection() {
        selectedAnnotationID = nil
        activeMoveSnapshot = nil
    }

    func mosaicImage(style: ScreenshotMosaicStyle) -> NSImage? {
        switch style {
        case .blur:
            if blurredImageCache == nil {
                blurredImageCache = Self.makeFilteredImage(
                    originalImage,
                    filterName: "CIGaussianBlur",
                    value: 12
                )
            }
            return blurredImageCache
        case .pixelate:
            if pixelatedImageCache == nil {
                pixelatedImageCache = Self.makePixelatedImage(originalImage, scale: 14)
            }
            return pixelatedImageCache
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedAnnotationID = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedAnnotationID = nil
    }

    var hasVisualEdits: Bool {
        !annotations.isEmpty || selectionRect != initialSelectionRect
    }

    func finalPNGData() -> Data {
        guard hasVisualEdits else { return originalOutputData }
        return renderedPNGData() ?? originalOutputData
    }

    @discardableResult
    func replaceBaseImage(with data: Data) -> Bool {
        guard let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else { return false }
        originalImage = image
        originalData = data
        if let outputRect {
            let capture = ScreenshotCapture(
                data: data,
                screenFrame: CGRect(origin: .zero, size: canvasSize)
            )
            originalOutputData = (try? ScreenshotService().crop(
                capture,
                to: outputRect,
                on: CGRect(origin: .zero, size: canvasSize)
            ).data) ?? data
        } else {
            originalOutputData = data
        }
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        selectedAnnotationID = nil
        blurredImageCache = nil
        pixelatedImageCache = nil
        return true
    }

    func renderedPNGData() -> Data? {
        guard let data = ScreenshotRenderPipeline().renderFullCanvas(
            image: originalImage,
            canvasSize: canvasSize,
            pixelScale: pixelScale,
            annotations: annotations,
            blurredImage: annotations.contains(where: { $0.kind == .mosaic && $0.mosaicStyle == .blur })
                ? mosaicImage(style: .blur)
                : nil,
            pixelatedImage: annotations.contains(where: { $0.kind == .mosaic && $0.mosaicStyle == .pixelate })
                ? mosaicImage(style: .pixelate)
                : nil
        ) else {
            return nil
        }
        guard let outputRect else { return data }
        let renderedCapture = ScreenshotCapture(
            data: data,
            screenFrame: CGRect(origin: .zero, size: canvasSize)
        )
        return try? ScreenshotService()
            .crop(
                renderedCapture,
                to: outputRect,
                on: CGRect(origin: .zero, size: canvasSize)
            )
            .data
    }

    private func append(_ annotation: ScreenshotAnnotation) {
        recordBeforeMutation()
        annotations.append(annotation)
        redoStack.removeAll()
    }

    private func recordBeforeMutation() {
        undoStack.append(annotations)
    }

    private var pixelScale: CGFloat {
        var proposedRect = NSRect(origin: .zero, size: canvasSize)
        guard let image = originalImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return 1
        }
        return max(1, CGFloat(image.width) / max(canvasSize.width, 1))
    }

    private static func makePixelatedImage(_ image: NSImage, scale: CGFloat) -> NSImage? {
        makeFilteredImage(image, filterName: "CIPixellate", value: scale)
    }

    private static func makeFilteredImage(_ image: NSImage, filterName: String, value: CGFloat) -> NSImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: filterName) else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        if filterName == "CIPixellate" {
            filter.setValue(value, forKey: kCIInputScaleKey)
        } else {
            filter.setValue(value, forKey: kCIInputRadiusKey)
        }
        guard let output = filter.outputImage,
              let rendered = CIContext(options: nil).createCGImage(output.cropped(to: input.extent), from: input.extent)
        else {
            return nil
        }
        return NSImage(cgImage: rendered, size: image.size)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}

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
                    ScreenshotSelectionOverlay(
                        editor: editor
                    )
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
                editor.updateSelectionRect(
                    clampedMove(moveStartRect, by: value.translation)
                )
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
                editor.updateSelectionRect(
                    resizedRect(resizeStartRect, handle: handle, by: value.translation)
                )
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
