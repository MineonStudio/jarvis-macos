import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 截图上的文字只有**一个**位置，三个渲染端都得落在它上面。
///
/// 用户报的「二次编辑出现双重」是两个毛病叠在一起：画布把正在编辑的那段文字又画了
/// 一遍（和输入控件里的那份叠着），而且剩下的那份还和输入控件差着几个点——预览用
/// SwiftUI `Text`、导出用非 flipped 的 `NSGraphicsContext`、输入控件是 `NSTextView`，
/// 三份排版各偏各的（22pt 时 4pt，72pt 时 14pt 上下）。所以这里有两条独立的钉子：
/// 编辑中的标注不再由画布画（`canvasAnnotations`），以及三个渲染端位置一致。
@MainActor
final class ScreenshotTextPlacementTests: XCTestCase {
    private let canvas = CGSize(width: 360, height: 240)
    private let anchor = CGPoint(x: 120, y: 90)
    private let sampleText = "对齐检查"

    private func makeEditor(fontSize: CGFloat = 22) -> ScreenshotEditorModel {
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        image.unlockFocus()
        let editor = ScreenshotEditorModel(
            image: image,
            data: Data(),
            outputData: Data(),
            canvasSize: canvas,
            outputRect: CGRect(origin: .zero, size: canvas)
        )
        editor.textFontSize = fontSize
        return editor
    }

    /// 红色墨迹的包围盒（画布坐标）。文字是红的，底图是白的。
    private func redInk(_ rep: NSBitmapImageRep, size: CGSize) -> CGRect? {
        let scaleX = CGFloat(rep.pixelsWide) / size.width
        let scaleY = CGFloat(rep.pixelsHigh) / size.height
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.redComponent > 0.4, color.greenComponent < 0.5 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(
            x: CGFloat(minX) / scaleX,
            y: CGFloat(minY) / scaleY,
            width: CGFloat(maxX - minX + 1) / scaleX,
            height: CGFloat(maxY - minY + 1) / scaleY
        )
    }

    /// 预览（SwiftUI 的画布图层）里这段文字的墨迹。
    private func previewInk(of annotation: ScreenshotAnnotation) throws -> CGRect {
        let content = ZStack(alignment: .topLeading) {
            Color.white
            ScreenshotAnnotationView(annotation: annotation, canvasSize: canvas, mosaicImage: nil)
        }
        .frame(width: canvas.width, height: canvas.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let cgImage = try XCTUnwrap(renderer.cgImage, "离屏渲染失败")
        return try XCTUnwrap(redInk(NSBitmapImageRep(cgImage: cgImage), size: canvas), "预览里没有画出文字")
    }

    /// 导出管线里这段文字的墨迹。
    private func exportInk(of annotation: ScreenshotAnnotation, editor: ScreenshotEditorModel) throws -> CGRect {
        let base = try XCTUnwrap(ScreenshotEditorModel.cgImage(from: editor.originalImage))
        let rendered = try XCTUnwrap(ScreenshotRenderPipeline().renderFullCanvas(
            ScreenshotRenderRequest(
                image: base,
                canvasSize: canvas,
                pixelScale: 1,
                annotations: [annotation],
                blurredImage: nil,
                pixelatedImage: nil
            )
        ))
        return try XCTUnwrap(redInk(NSBitmapImageRep(cgImage: rendered), size: canvas), "导出里没有画出文字")
    }

    /// 把画布真的渲染进窗口（输入控件是 AppKit 子视图，离屏渲染看不到它），
    /// 返回红色墨迹在指定横向窗口内的上下沿。
    private func canvasInk(
        _ editor: ScreenshotEditorModel,
        columns: (minX: CGFloat, maxX: CGFloat)? = nil
    ) throws -> CGRect {
        let view = ScreenshotCanvasView(
            image: editor.originalImage,
            editor: editor,
            interactive: true,
            showsSelectionOverlay: false
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: canvas)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: canvas),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        defer { window.orderOut(nil) }

        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let scaleX = CGFloat(rep.pixelsWide) / canvas.width
        let scaleY = CGFloat(rep.pixelsHigh) / canvas.height

        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for y in 0 ..< rep.pixelsHigh {
            for x in 0 ..< rep.pixelsWide {
                let canvasX = CGFloat(x) / scaleX
                if let columns, canvasX < columns.minX || canvasX > columns.maxX {
                    continue
                }
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.redComponent > 0.4, color.greenComponent < 0.5 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return .zero }
        return CGRect(
            x: CGFloat(minX) / scaleX,
            y: CGFloat(minY) / scaleY,
            width: CGFloat(maxX - minX + 1) / scaleX,
            height: CGFloat(maxY - minY + 1) / scaleY
        )
    }

    /// 正在编辑的那段文字由输入控件负责显示，画布不能再画一遍。
    func testEditingAnnotationIsLeftToTheInlineEditor() throws {
        let editor = makeEditor()
        editor.addText(alignedAtLeft: anchor, text: sampleText)
        editor.addText(alignedAtLeft: CGPoint(x: 60, y: 180), text: "另一段")
        let annotation = try XCTUnwrap(editor.annotations.first)
        let view = ScreenshotCanvasView(
            image: editor.originalImage,
            editor: editor,
            interactive: true
        )

        XCTAssertEqual(view.canvasAnnotations.count, 2, "没在编辑时，所有标注都该画")

        editor.beginTextEditing(id: annotation.id)

        XCTAssertEqual(
            view.canvasAnnotations.map(\.id),
            editor.annotations.dropFirst().map(\.id),
            "正在编辑的那段文字不该再由画布画一遍（会和输入控件里的那份叠着）"
        )
    }

    /// 多行文字在编辑期间不能凭空少掉几行。
    ///
    /// 输入控件是单行的（回车即确认），顶上去只显示第一行。多行只可能来自旧数据，
    /// 这种标注就继续由画布画着——上面那条「让位给输入控件」的规则对它不适用。
    func testMultiLineTextStaysOnTheCanvasWhileEditing() throws {
        let editor = makeEditor()
        editor.addText(alignedAtLeft: anchor, text: "第一行\n第二行")
        let annotation = try XCTUnwrap(editor.annotations.first)
        editor.addText(alignedAtLeft: CGPoint(x: 60, y: 180), text: "单行")
        let view = ScreenshotCanvasView(
            image: editor.originalImage,
            editor: editor,
            interactive: true
        )

        editor.beginTextEditing(id: annotation.id)

        XCTAssertEqual(
            view.canvasAnnotations.count,
            2,
            "多行文字在编辑期间被抽走了——单行输入控件显示不了第 2..n 行"
        )
    }

    /// 文字是正着画的，不是上下镜像的。
    ///
    /// 包围盒对「镜像」是不变量：三条渲染路径一起翻过来，上面那些位置断言照样全绿。
    /// 所以这里用一个上宽下窄的字（"T"）：上半部分的墨迹明显比下半部分宽，镜像了就反过来。
    func testTextIsNotDrawnUpsideDown() throws {
        let editor = makeEditor(fontSize: 44)
        editor.addText(alignedAtLeft: anchor, text: "T")
        let annotation = try XCTUnwrap(editor.annotations.first)

        for preview in [true, false] {
            let label = preview ? "预览" : "导出"
            let rows = try inkRows(of: annotation, editor: editor, preview: preview)
            XCTAssertGreaterThan(rows.count, 10, "\(label)里没画出 \"T\"")
            let band = max(1, rows.count / 5)
            let topWidth = averageWidth(rows, in: 0 ..< band)
            let bottomWidth = averageWidth(rows, in: (rows.count - band) ..< rows.count)
            XCTAssertGreaterThan(
                topWidth,
                bottomWidth + 3,
                "\(label)里的 \"T\" 上下颠倒了（上半 \(topWidth)pt，下半 \(bottomWidth)pt）"
            )
        }
    }

    /// 逐行的墨迹宽度（画布坐标，行序自上而下）：镜像时上下会互换。
    private func inkRows(
        of annotation: ScreenshotAnnotation,
        editor: ScreenshotEditorModel,
        preview: Bool
    ) throws -> [CGFloat] {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        if preview {
            let content = ZStack(alignment: .topLeading) {
                Color.white
                ScreenshotAnnotationView(annotation: annotation, canvasSize: canvas, mosaicImage: nil)
            }
            .frame(width: canvas.width, height: canvas.height)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let cgImage = try XCTUnwrap(renderer.cgImage)
            rep = NSBitmapImageRep(cgImage: cgImage)
            scale = CGFloat(rep.pixelsWide) / canvas.width
        } else {
            let base = try XCTUnwrap(ScreenshotEditorModel.cgImage(from: editor.originalImage))
            let rendered = try XCTUnwrap(ScreenshotRenderPipeline().renderFullCanvas(
                ScreenshotRenderRequest(
                    image: base,
                    canvasSize: canvas,
                    pixelScale: 1,
                    annotations: [annotation],
                    blurredImage: nil,
                    pixelatedImage: nil
                )
            ))
            rep = NSBitmapImageRep(cgImage: rendered)
            scale = 1
        }

        var rows: [CGFloat] = []
        for y in 0 ..< rep.pixelsHigh {
            var minX = Int.max, maxX = Int.min
            for x in 0 ..< rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.redComponent > 0.4, color.greenComponent < 0.5 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
            }
            if minX <= maxX {
                rows.append(CGFloat(maxX - minX + 1) / scale)
            }
        }
        return rows
    }

    private func averageWidth(_ rows: [CGFloat], in range: Range<Int>) -> CGFloat {
        let clamped = range.clamped(to: 0 ..< rows.count)
        guard !clamped.isEmpty else { return 0 }
        return clamped.map { rows[$0] }.reduce(0, +) / CGFloat(clamped.count)
    }

    /// 预览和导出画的必须是同一处的同一份文字，字号多大都一样。
    ///
    /// 这条钉住的是排版公式的分家：预览原来用 SwiftUI `Text`，它的行框落点与 AppKit
    /// 的文本绘制对不上，而且偏差随字号长（44pt 时能差出 6pt）。
    func testPreviewAndExportAgreeOnWhereTheTextGoes() throws {
        for fontSize in [12.0, 22.0, 44.0] as [CGFloat] {
            let editor = makeEditor(fontSize: fontSize)
            editor.addText(alignedAtLeft: anchor, text: sampleText)
            let annotation = try XCTUnwrap(editor.annotations.first)

            let preview = try previewInk(of: annotation)
            let export = try exportInk(of: annotation, editor: editor)

            XCTAssertEqual(preview.minX, export.minX, accuracy: 1.5, "字号 \(fontSize)：预览与导出的文字左边对不上")
            XCTAssertEqual(preview.minY, export.minY, accuracy: 1.5, "字号 \(fontSize)：预览与导出的文字上边对不上")
            XCTAssertEqual(preview.maxY, export.maxY, accuracy: 1.5, "字号 \(fontSize)：预览与导出的文字下边对不上")
        }
    }

    /// 编辑中，画布上出现的就是草稿那一份，不多也不少。
    ///
    /// 只看位置抓不住「画了两份」：两份完全重合时位置当然一致，用户看到的是字变糊
    /// （两份抗锯齿叠加）。所以这里让草稿和原文不一样——原文要是还在画，墨迹会多出
    /// 中文那一份的高和宽。
    func testOnlyTheDraftIsLeftOnTheCanvasWhileReediting() throws {
        let draft = "abc"

        // 基准：同样一段草稿，提交之后画布上该有的样子。
        let draftOnly = makeEditor()
        draftOnly.addText(alignedAtLeft: anchor, text: draft)
        let expected = try canvasInk(draftOnly)
        XCTAssertFalse(expected.isEmpty, "基准渲染里没有文字")

        // 实际：一段写好的中文标注正被重新编辑，草稿换成了拉丁小写。
        let editor = makeEditor()
        editor.addText(alignedAtLeft: anchor, text: sampleText)
        let annotation = try XCTUnwrap(editor.annotations.first)
        editor.beginTextEditing(id: annotation.id)
        editor.textDraft = draft

        let rendered = try canvasInk(editor)
        XCTAssertEqual(
            rendered.maxX,
            expected.maxX,
            accuracy: 2.5,
            "画布上还留着原文——它比草稿宽"
        )

        // 高度只在文字中段比：光标停在文字的一头，比字高。
        let columns = (
            minX: expected.minX + expected.width * 0.25,
            maxX: expected.minX + expected.width * 0.75
        )
        let expectedRows = try canvasInk(draftOnly, columns: columns)
        let renderedRows = try canvasInk(editor, columns: columns)
        XCTAssertEqual(renderedRows.minY, expectedRows.minY, accuracy: 1.5, "画布上叠着原文那一份")
        XCTAssertEqual(renderedRows.maxY, expectedRows.maxY, accuracy: 1.5, "画布上叠着原文那一份")
    }

    /// 点进二次编辑，画面上的文字不该动——既不重影，也不上下跳。
    ///
    /// 重影是「画布 + 输入控件各画一份」；跳是两者位置本就差着几个点。两者都会让
    /// 用户看到「点一下，字就变了样」。
    func testReeditingShowsOneCopyWhereTheTextAlreadyIs() throws {
        let editor = makeEditor()
        editor.addText(alignedAtLeft: anchor, text: sampleText)
        let annotation = try XCTUnwrap(editor.annotations.first)

        let committedAll = try canvasInk(editor)
        XCTAssertFalse(committedAll.isEmpty, "提交后画布上没有文字")
        // 只量文字中段：光标停在文字的一头，不要把它量进来（它比字高）。
        let columns = (
            minX: committedAll.minX + committedAll.width * 0.25,
            maxX: committedAll.minX + committedAll.width * 0.75
        )
        XCTAssertGreaterThan(columns.maxX, columns.minX)

        let committed = try canvasInk(editor, columns: columns)
        editor.beginTextEditing(id: annotation.id)
        let editing = try canvasInk(editor, columns: columns)

        XCTAssertEqual(editing.minY, committed.minY, accuracy: 1.5, "点进编辑后文字上下跳了")
        XCTAssertEqual(editing.maxY, committed.maxY, accuracy: 1.5, "点进编辑后文字上下跳了（或画了第二份）")
        XCTAssertEqual(editing.minX, committed.minX, accuracy: 1.5, "点进编辑后文字左右跳了")
    }
}
