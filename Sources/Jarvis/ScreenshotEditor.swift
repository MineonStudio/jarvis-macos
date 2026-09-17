import AppKit
import CoreImage
import SwiftUI
import Translation

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

enum ScreenshotLineStyle: String, CaseIterable, Identifiable, Equatable {
    case solid
    case dashed

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .solid: "实线"
        case .dashed: "虚线"
        }
    }

    var icon: String {
        switch self {
        case .solid: "rectangle"
        case .dashed: "rectangle.dashed"
        }
    }

    var dashPattern: [CGFloat] {
        switch self {
        case .solid: []
        case .dashed: [10, 6]
        }
    }
}

struct ScreenshotAnnotation: Identifiable, Equatable, Sendable {
    enum Kind: Equatable {
        case arrow
        case rectangle
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
    var lineStyle: ScreenshotLineStyle = .solid
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
        let xValues = points.map(\.x)
        let yValues = points.map(\.y)
        let minX = xValues.min() ?? 0
        let minY = yValues.min() ?? 0
        let maxX = xValues.max() ?? minX
        let maxY = yValues.max() ?? minY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
        case .rectangle:
            return rect.insetBy(dx: -(lineWidth / 2 + 4), dy: -(lineWidth / 2 + 4))
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

    /// 内联文字输入框的锚点。为 nil 表示当前没有在编辑文字。
    ///
    /// 草稿本身留在画布视图（TextEditor 直接绑定它），但「正在编辑」这件事必须在
    /// 模型里可读：Esc 的分级处理要据此决定是取消这次输入，还是退出整场截图。
    /// 正在导出（渲染 + 编码在后台跑）。导出期间禁用导出相关按钮，避免重复触发。
    @Published private(set) var isExporting = false
    @Published var textInputAnchor: CGPoint?
    /// 正在编辑的既有文字标注 id；新建时为 nil。
    @Published var editingTextID: UUID?

    @Published private(set) var selectionRect: CGRect? {
        didSet { scheduleRenderedTranslationBlocksRefresh() }
    }

    /// 译文块变化（每收到一条译文就变一次）也要重排，但同一轮里合并成一次。
    @Published var translationBlocks: [ScreenshotTranslationBlock] = [] {
        didSet { scheduleRenderedTranslationBlocksRefresh() }
    }

    var isTranslationLayoutRefreshScheduled = false
    @Published var mosaicBrushSize: CGFloat = 28
    @Published var mosaicMode: ScreenshotMosaicMode = .rectangle
    @Published var mosaicStyle: ScreenshotMosaicStyle = .blur
    @Published var arrowColor: ScreenshotTextColor = .red
    @Published var arrowLineWidth: CGFloat = 5
    @Published var arrowHeadSize: CGFloat = 20
    @Published var arrowHeadStyle: ScreenshotArrowHeadStyle = .filled
    @Published var rectangleColor: ScreenshotTextColor = .red
    @Published var rectangleLineWidth: CGFloat = 5
    @Published var rectangleLineStyle: ScreenshotLineStyle = .solid
    @Published var textFontSize: CGFloat = 22
    @Published var textColor: ScreenshotTextColor = .red
    @Published var textBold = true
    @Published var textItalic = false
    @Published var textStrikethrough = false
    @Published private(set) var annotations: [ScreenshotAnnotation] = []
    @Published private(set) var redoStack: [[ScreenshotAnnotation]] = []
    @Published var translationMode = false
    /// 译文块的排版结果。缓存而不是每次视图更新现算——见
    /// `scheduleRenderedTranslationBlocksRefresh()`。
    /// 只能由 `refreshRenderedTranslationBlocks()` 写，别在别处赋值。
    @Published var renderedTranslationBlocks: [ScreenshotTranslationRenderBlock] = []
    @Published var translationVisible = true {
        didSet { scheduleRenderedTranslationBlocksRefresh() }
    }

    @Published var translationTargetLanguage: ScreenshotTranslationLanguage
    @Published var translationState: ScreenshotTranslationState = .idle
    @Published var translationSourceRect: CGRect? {
        didSet { scheduleRenderedTranslationBlocksRefresh() }
    }

    @Published var appleTranslationConfiguration: TranslationSession.Configuration?

    private let coordinateSpace: ScreenshotCoordinateSpace
    private let initialSelectionRect: CGRect?
    private var undoStack: [[ScreenshotAnnotation]] = []
    private var activeMoveSnapshot: [ScreenshotAnnotation]?
    var translationTask: Task<Void, Never>?
    var translationGeneration = 0
    var pendingAppleTranslationJob: ScreenshotAppleTranslationJob?
    var appleTranslationJobContinuation: CheckedContinuation<Void, Error>?
    var appleTranslationSourceBlocks: [UUID: ScreenshotOCRBlock] = [:]
    var translationProgress: ScreenshotTranslationProgress?
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
        translationTargetLanguage = ScreenshotTranslationConfiguration.loadTargetLanguage()
        translationSourceRect = nil
        translationProgress = nil
    }

    deinit {
        translationTask?.cancel()
        appleTranslationJobContinuation?.resume(throwing: CancellationError())
    }
}

extension ScreenshotEditorModel {
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
        if translationSourceRect != nil || !translationBlocks.isEmpty || translationState.isRunning {
            clearTranslation()
        }
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
        translationMode
            || selectedTool == .arrow
            || selectedTool == .rectangle
            || selectedTool == .mosaic
            || selectedTool == .text
    }

    var isEditingText: Bool {
        textInputAnchor != nil
    }

    /// 在指定位置开始输入一段新文字。
    func beginTextEditing(at point: CGPoint) {
        textInputAnchor = point
        editingTextID = nil
    }

    /// 结束内联输入（提交与取消都走它）。
    func endTextEditing() {
        textInputAnchor = nil
        editingTextID = nil
    }

    /// Esc 的分级处理：正在输入文字就先取消这次输入；选中了标注就取消选中；
    /// 两者都没有才把手交给调用方去结束整场截图。
    ///
    /// 原来所有 Esc 都直达「结束整场」——打字打到一半本能按 Esc，整张截图连同
    /// 已经画好的标注一起没了。
    /// - Returns: 这次 Esc 是否已经被消化。
    @discardableResult
    func handleEscape() -> Bool {
        if isEditingText {
            endTextEditing()
            return true
        }
        if selectedAnnotationID != nil {
            clearSelection()
            return true
        }
        return false
    }

    func selectTool(_ tool: ScreenshotTool?) {
        // 换工具时把内联输入收掉：否则锚点留在模型里，Esc 的第一步会被一个
        // 已经不存在的「正在输入」永远吃掉。
        endTextEditing()
        selectedTool = tool
        translationMode = false
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

    func addRectangle(from start: CGPoint, to end: CGPoint) {
        guard distance(from: start, to: end) > 8 else { return }
        append(.init(
            kind: .rectangle,
            points: [start, end],
            text: nil,
            brushSize: rectangleLineWidth,
            color: rectangleColor,
            lineWidth: rectangleLineWidth,
            lineStyle: rectangleLineStyle
        ))
    }

    func addMosaic(points: [CGPoint]) {
        guard points.count > 1 else { return }
        // 点一下就松手会留下宽高为 0 的马赛克：画面上看不见、也永远选不中删不掉，
        // 却让 hasVisualEdits 为真，之后每次导出都走昂贵的渲染路径。
        if mosaicMode == .rectangle {
            let rect = CGRect(
                x: min(points[0].x, points[1].x),
                y: min(points[0].y, points[1].y),
                width: abs(points[1].x - points[0].x),
                height: abs(points[1].y - points[0].y)
            )
            guard rect.width >= 4, rect.height >= 4 else { return }
        } else {
            let length = zip(points, points.dropFirst()).reduce(0.0) { total, pair in
                total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
            }
            guard length >= 8 else { return }
        }
        append(.init(
            kind: .mosaic,
            points: points,
            text: nil,
            brushSize: mosaicBrushSize,
            mosaicMode: mosaicMode,
            mosaicStyle: mosaicStyle
        ))
    }

    func addText(alignedAtLeft point: CGPoint, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var annotation = ScreenshotAnnotation(
            kind: .text,
            points: [point],
            text: text,
            brushSize: 0,
            fontSize: textFontSize,
            textColor: textColor,
            isBold: textBold,
            isItalic: textItalic,
            isStrikethrough: textStrikethrough
        )
        annotation.points = [textCenter(alignedAtLeft: point, for: annotation)]
        append(annotation)
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

    func updateText(id: UUID, text: String, alignedAtLeft point: CGPoint?) {
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
        if let point {
            updated.points = [textCenter(alignedAtLeft: point, for: updated)]
        }
        guard updated != annotations[index] else { return }
        recordBeforeMutation()
        annotations[index] = updated
        redoStack.removeAll()
    }

    private func textCenter(alignedAtLeft point: CGPoint, for annotation: ScreenshotAnnotation) -> CGPoint {
        CGPoint(
            x: point.x + annotation.textSize.width / 2 - 9,
            y: point.y
        )
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
}

extension ScreenshotEditorModel {
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
        // 拖动还没结束时按 ⌘Z：过期快照会入栈并把重做历史清空。
        activeMoveSnapshot = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedAnnotationID = nil
    }

    func redo() {
        activeMoveSnapshot = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedAnnotationID = nil
    }

    var hasVisualEdits: Bool {
        !annotations.isEmpty
            || selectionRect != initialSelectionRect
            || (translationVisible && !translationBlocks.isEmpty)
    }

    func finalPNGData() async -> Data {
        guard hasVisualEdits else { return originalOutputData }
        return await renderedPNGData() ?? originalOutputData
    }

    /// 导出用的 PNG。
    ///
    /// 渲染与编码都在后台任务上跑：6K 画布上整段是几百毫秒到数秒的量级，压在主
    /// 线程就是点「完成」之后界面直接卡死几秒。
    func renderedPNGData() async -> Data? {
        // 排版是合并刷新的，导出前先确保拿到的是最新结果。
        refreshRenderedTranslationBlocks()
        guard let baseImage = Self.cgImage(from: originalImage) else { return nil }
        let blurred = annotations.contains { $0.kind == .mosaic && $0.mosaicStyle == .blur }
            ? Self.cgImage(from: mosaicImage(style: .blur))
            : nil
        let pixelated = annotations.contains { $0.kind == .mosaic && $0.mosaicStyle == .pixelate }
            ? Self.cgImage(from: mosaicImage(style: .pixelate))
            : nil
        let request = ScreenshotRenderRequest(
            image: baseImage,
            canvasSize: canvasSize,
            pixelScale: pixelScale,
            annotations: annotations,
            blurredImage: blurred,
            pixelatedImage: pixelated,
            translations: renderedTranslationBlocks,
            showsTranslation: translationVisible
        )
        let canvasSize = canvasSize
        let outputRect = outputRect
        isExporting = true
        defer { isExporting = false }
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let rendered = ScreenshotRenderPipeline().renderFullCanvas(request) else {
                return nil
            }
            guard let outputRect else {
                return Self.pngData(from: rendered)
            }
            // 只裁需要的区域：直接在渲染好的位图上切，不再把整幅编码成 PNG、解码
            // 回来、裁剪、再编码一次。6K 画布上那三步是秒级的无用功。
            guard let cropped = Self.crop(rendered, toOutputRect: outputRect, canvasSize: canvasSize) else {
                return nil
            }
            return Self.pngData(from: cropped)
        }.value
    }

    nonisolated static func cgImage(from image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private nonisolated static func crop(
        _ image: CGImage,
        toOutputRect outputRect: CGRect,
        canvasSize: CGSize
    ) -> CGImage? {
        let coordinateSpace = ScreenshotCoordinateSpace(
            screenFrame: CGRect(origin: .zero, size: canvasSize),
            canvasSize: canvasSize
        )
        // CGImage 的坐标是「左上角原点、y 向下」，与画布坐标一致；输出矩形是
        // AppKit 那套 y 向上的，先用已有的换算转过去。
        let canvasRect = coordinateSpace.canvasRect(fromOutputRect: outputRect)
        let scaleX = CGFloat(image.width) / canvasSize.width
        let scaleY = CGFloat(image.height) / canvasSize.height
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelRect = CGRect(
            x: canvasRect.minX * scaleX,
            y: canvasRect.minY * scaleY,
            width: canvasRect.width * scaleX,
            height: canvasRect.height * scaleY
        ).integral.intersection(bounds)
        guard !pixelRect.isEmpty else { return nil }
        return image.cropping(to: pixelRect)
    }

    private nonisolated static func pngData(from image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
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
