import AppKit
@testable import Jarvis
import SwiftUI
import XCTest

/// 编辑器里几处原本零覆盖的行为：撤销栈、零尺寸标注、以及工具栏视图本身能不能
/// 渲染出来（原来从未被实例化过——把保存和完成的 action 接反，三套测试也会全绿）。
@MainActor
final class ScreenshotEditorBehaviorTests: XCTestCase {
    private func makeEditor() throws -> ScreenshotEditorModel {
        let canvas = CGSize(width: 400, height: 300)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        image.unlockFocus()
        let data = try XCTUnwrap(image.tiffRepresentation)
        return ScreenshotEditorModel(
            image: image,
            data: data,
            outputData: data,
            canvasSize: canvas
        )
    }

    func testUndoRedoWalksTheAnnotationStack() throws {
        let editor = try makeEditor()
        editor.addRectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        editor.addArrow(from: CGPoint(x: 80, y: 80), to: CGPoint(x: 140, y: 120))
        XCTAssertEqual(editor.annotations.count, 2)
        XCTAssertTrue(editor.canUndo)

        editor.undo()
        XCTAssertEqual(editor.annotations.count, 1)
        XCTAssertTrue(editor.canRedo)

        editor.redo()
        XCTAssertEqual(editor.annotations.count, 2)
        XCTAssertFalse(editor.canRedo)
    }

    /// 撤销之后再画一笔，重做历史必须作废（否则会把被撤销的分支又接回来）。
    func testNewAnnotationClearsTheRedoStack() throws {
        let editor = try makeEditor()
        editor.addRectangle(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 60))
        editor.undo()
        XCTAssertTrue(editor.canRedo)

        editor.addArrow(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 260, y: 240))
        XCTAssertFalse(editor.canRedo)
    }

    /// 点一下就松手不该留下看不见、也删不掉的零尺寸马赛克。
    func testZeroSizeMosaicIsIgnored() throws {
        let editor = try makeEditor()
        editor.mosaicMode = .rectangle
        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 50)])
        XCTAssertTrue(editor.annotations.isEmpty, "零尺寸马赛克应当被丢弃")

        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 80, y: 80)])
        XCTAssertEqual(editor.annotations.count, 1, "正常尺寸仍要能画上")
    }

    func testZeroLengthBrushStrokeIsIgnored() throws {
        let editor = try makeEditor()
        editor.mosaicMode = .brush
        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 51, y: 50)])
        XCTAssertTrue(editor.annotations.isEmpty)

        editor.addMosaic(points: [CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)])
        XCTAssertEqual(editor.annotations.count, 1)
    }

    /// 工具栏视图本身（不是单个图标）从未被实例化过：接错 action、行序写反、把胶囊
    /// 排在错误的顺序上，都不会有任何测试信号。这里让它真的渲染一次。
    func testToolbarRendersInBothRowOrders() throws {
        let editor = try makeEditor()
        let layout = ScreenshotToolbarLayoutModel(width: ScreenshotToolbarMetrics.baseWidth)

        for placesAbove in [false, true] {
            layout.placesSecondaryRowAboveMain = placesAbove
            for tool in [ScreenshotTool.arrow, .mosaic, .text] {
                editor.selectTool(tool)
                let size = NSHostingView(
                    rootView: ScreenshotToolbar(editor: editor, layout: layout, onAction: { _ in })
                ).fittingSize
                XCTAssertEqual(
                    size.height,
                    ScreenshotToolbarMetrics.expandedHeight,
                    accuracy: 1,
                    "展开态的高度应当与交给面板的口径一致（placesAbove=\(placesAbove)）"
                )
                XCTAssertGreaterThan(size.width, 0)
            }
            editor.selectTool(nil)
            let collapsed = NSHostingView(
                rootView: ScreenshotToolbar(editor: editor, layout: layout, onAction: { _ in })
            ).fittingSize
            XCTAssertEqual(
                collapsed.height,
                ScreenshotToolbarMetrics.compactHeight,
                accuracy: 1
            )
        }
    }
}

extension ScreenshotEditorBehaviorTests {
    /// 编辑历史截图时，选区必须是**画布**坐标（缩放后的尺寸），不是原图像素尺寸。
    ///
    /// 原来两者混用：图比屏幕大时选区有一部分落在画布外（手柄看不到），工具栏按原图
    /// 尺寸定位会偏出画面，中键贴图更是生成一个比屏幕还大的窗口。
    func testHistoryEditingSelectionUsesCanvasCoordinates() {
        let imageSize = CGSize(width: 1512, height: 982)
        let fitted = CGSize(width: 1260, height: 818)
        let origin = CGPoint(x: 100, y: 60)

        let image = NSImage(size: imageSize)
        let editor = ScreenshotEditorModel(
            image: image,
            data: Data(),
            outputData: Data(),
            canvasSize: fitted,
            outputRect: CGRect(origin: .zero, size: fitted)
        )

        // 选区铺满画布。
        XCTAssertEqual(editor.selectionRect, CGRect(origin: .zero, size: fitted))

        // 它映射回屏幕时应当落在承载窗口的位置上，且尺寸是缩放过的那份。
        let screenFrame = CGRect(origin: origin, size: fitted)
        XCTAssertEqual(
            editor.selectionFrame(on: screenFrame),
            CGRect(origin: origin, size: fitted)
        )
    }
}

extension ScreenshotEditorBehaviorTests {
    /// 文本编辑：换行原样保留，不再按「输入框宽度」硬折行。
    func testCommittedTextKeepsTheUsersLineBreaks() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 120, y: 90))
        editor.textDraft = "第一行\n第二行\n\n第四行"

        XCTAssertTrue(editor.commitTextEditing())

        let annotation = try XCTUnwrap(editor.annotations.first)
        XCTAssertEqual(annotation.kind, .text)
        XCTAssertEqual(annotation.text, "第一行\n第二行\n\n第四行")
        // 行数影响占位高度，多行必须比单行高。
        XCTAssertGreaterThan(annotation.textSize.height, editor.textFontSize * 2)
    }

    /// 编辑器没有确认按钮，「换工具」就是提交时机。
    func testSwitchingToolsCommitsTheDraft() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 60, y: 60))
        editor.textDraft = "随手记一句"

        editor.selectTool(.arrow)

        XCTAssertFalse(editor.isEditingText)
        XCTAssertEqual(editor.annotations.count, 1, "换工具时草稿应当落下去，而不是被丢掉")
        XCTAssertEqual(editor.annotations.first?.text, "随手记一句")
    }

    /// 空草稿只是收起输入框，不留空标注。
    func testCommittingAnEmptyDraftLeavesNoAnnotation() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 60, y: 60))
        editor.textDraft = "   \n  "

        XCTAssertFalse(editor.commitTextEditing())
        XCTAssertTrue(editor.annotations.isEmpty)
        XCTAssertFalse(editor.isEditingText)
    }

    /// Esc 仍然是「丢弃这次输入」。
    func testEscapeDiscardsTheDraft() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 60, y: 60))
        editor.textDraft = "不要这段"

        XCTAssertTrue(editor.handleEscape())

        XCTAssertTrue(editor.annotations.isEmpty)
        XCTAssertFalse(editor.isEditingText)
        XCTAssertTrue(editor.textDraft.isEmpty)
    }

    /// 编辑既有文字时按「先提交后重开」的顺序，不能把原来的文字弄丢。
    func testReopeningAnExistingTextKeepsItsContent() throws {
        let editor = try makeEditor()
        editor.addText(alignedAtLeft: CGPoint(x: 40, y: 40), text: "原文")
        let id = try XCTUnwrap(editor.annotations.first?.id)

        editor.textInputAnchor = CGPoint(x: 40, y: 40)
        editor.editingTextID = id
        editor.textDraft = "改过的文字"
        XCTAssertTrue(editor.commitTextEditing())

        XCTAssertEqual(editor.annotations.count, 1, "应当是更新而不是新增")
        XCTAssertEqual(editor.annotations.first?.text, "改过的文字")
    }
}

extension ScreenshotEditorBehaviorTests {
    /// 拖动正在编辑的文字之后，提交不能把它拽回原位。
    ///
    /// `updateText(alignedAtLeft:)` 用的是输入框那个锚点；锚点不跟着拖动走的话，
    /// 提交时会把文字放回拖动前的位置——用户看到的是「拖了，然后又弹回去了」。
    func testMovingTheTextWhileEditingKeepsTheNewPosition() throws {
        let editor = try makeEditor()
        editor.addText(alignedAtLeft: CGPoint(x: 80, y: 70), text: "原位")
        let id = try XCTUnwrap(editor.annotations.first?.id)
        let originalStart = try XCTUnwrap(editor.annotations.first?.start)

        // 重新进入编辑，再把它拖走。
        editor.textInputAnchor = CGPoint(x: 80, y: 70)
        editor.editingTextID = id
        editor.textDraft = "原位"
        let anchorBefore = try XCTUnwrap(editor.textInputAnchor)

        editor.beginMove(id: id)
        editor.moveAnnotation(id: id, by: CGPoint(x: 40, y: 25))
        editor.endMove()

        // 锚点必须跟标注一起走。
        XCTAssertEqual(editor.textInputAnchor?.x ?? 0, anchorBefore.x + 40, accuracy: 0.001)
        XCTAssertEqual(editor.textInputAnchor?.y ?? 0, anchorBefore.y + 25, accuracy: 0.001)

        XCTAssertTrue(editor.commitTextEditing())
        let moved = try XCTUnwrap(editor.annotations.first)
        XCTAssertEqual(moved.start.x, originalStart.x + 40, accuracy: 0.001, "提交把文字拽回了原位")
        XCTAssertEqual(moved.start.y, originalStart.y + 25, accuracy: 0.001)
    }
}

extension ScreenshotEditorBehaviorTests {
    /// 编辑状态下按住输入区拖动：已有的标注跟着走，锚点一起走。
    func testDraggingWhileEditingMovesTheExistingText() throws {
        let editor = try makeEditor()
        editor.addText(alignedAtLeft: CGPoint(x: 70, y: 50), text: "拖我")
        let id = try XCTUnwrap(editor.annotations.first?.id)
        let originalStart = try XCTUnwrap(editor.annotations.first?.start)

        // 进入编辑态（锚点按反推公式还原）。
        editor.textInputAnchor = ScreenshotCanvasView.textEditingAnchor(for: editor.annotations[0])
        editor.editingTextID = id
        let anchorBefore = try XCTUnwrap(editor.textInputAnchor)

        editor.moveTextEditing(by: CGPoint(x: 30, y: -20))

        XCTAssertEqual(editor.annotations[0].start.x, originalStart.x + 30, accuracy: 0.001)
        XCTAssertEqual(editor.annotations[0].start.y, originalStart.y - 20, accuracy: 0.001)
        XCTAssertEqual(editor.textInputAnchor?.x ?? 0, anchorBefore.x + 30, accuracy: 0.001)
        XCTAssertEqual(editor.textInputAnchor?.y ?? 0, anchorBefore.y - 20, accuracy: 0.001)
    }

    /// 新建文字还没落盘时拖动：拖的是输入框本身（锚点），不留空标注。
    func testDraggingWhileTypingMovesTheAnchorOnly() throws {
        let editor = try makeEditor()
        editor.beginTextEditing(at: CGPoint(x: 100, y: 60))
        editor.textDraft = "正在打"

        editor.moveTextEditing(by: CGPoint(x: 15, y: 12))

        XCTAssertEqual(editor.textInputAnchor?.x ?? 0, 115, accuracy: 0.001)
        XCTAssertEqual(editor.textInputAnchor?.y ?? 0, 72, accuracy: 0.001)
        XCTAssertTrue(editor.annotations.isEmpty)

        // 拖到哪儿就在哪儿落盘。
        XCTAssertTrue(editor.commitTextEditing())
        let committed = try XCTUnwrap(editor.annotations.first)
        XCTAssertEqual(committed.start.x, 115 + committed.textSize.width / 2 - 9, accuracy: 0.001)
    }
}

/// 文字工具下「点一下」该做什么。
///
/// 这条规则已经被漏过一次：正在编辑时点别处，本该是「确认」，结果既提交了又顺手
/// 在同一处开了新的一段，把刚打的草稿也清了。把判定抽出来钉住。
final class ScreenshotTextToolTapTests: XCTestCase {
    private let existingID = UUID()

    func testClickingAwayWhileEditingOnlyConfirms() {
        XCTAssertEqual(
            ScreenshotCanvasView.textToolTapOutcome(
                isEditing: true,
                existingAnnotationID: nil,
                dragDistance: 0
            ),
            .commitOnly,
            "正在编辑时点别处应当是确认，而不是新开一段"
        )
    }

    func testClickingWhenNotEditingStartsANewText() {
        XCTAssertEqual(
            ScreenshotCanvasView.textToolTapOutcome(
                isEditing: false,
                existingAnnotationID: nil,
                dragDistance: 0
            ),
            .beginNew
        )
    }

    func testTappingAnExistingTextOpensItForEditing() {
        XCTAssertEqual(
            ScreenshotCanvasView.textToolTapOutcome(
                isEditing: false,
                existingAnnotationID: existingID,
                dragDistance: 0
            ),
            .commitThenEditExisting(existingID)
        )
        XCTAssertEqual(
            ScreenshotCanvasView.textToolTapOutcome(
                isEditing: true,
                existingAnnotationID: existingID,
                dragDistance: 0
            ),
            .commitThenEditExisting(existingID),
            "在别处编辑时点到另一段文字，应当先提交再切过去"
        )
    }

    /// 拖出去的那一下（不是点击）只提交，不开任何输入区——拖动本身是移动文字。
    func testDraggingOnlyCommits() {
        XCTAssertEqual(
            ScreenshotCanvasView.textToolTapOutcome(
                isEditing: false,
                existingAnnotationID: nil,
                dragDistance: 40
            ),
            .commitOnly
        )
        XCTAssertEqual(
            ScreenshotCanvasView.textToolTapOutcome(
                isEditing: true,
                existingAnnotationID: existingID,
                dragDistance: 40
            ),
            .commitOnly
        )
    }
}
