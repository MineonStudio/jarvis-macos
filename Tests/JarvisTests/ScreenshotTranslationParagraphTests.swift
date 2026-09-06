import AppKit
@testable import Jarvis
import XCTest

extension ScreenshotTranslationTests {
    func testTranslationLayoutExpandsIntoTheGapWithoutOverlappingTheNextBlock() {
        let first = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "File",
            translatedText: "一个更长的菜单项",
            bounds: CGRect(x: 100, y: 40, width: 40, height: 20),
            confidence: 0.9
        )
        let second = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "Edit",
            translatedText: "编辑",
            bounds: CGRect(x: 220, y: 40, width: 40, height: 20),
            confidence: 0.9
        )

        let layout = ScreenshotTranslationLayout.apply(
            to: [first, second],
            canvasSize: CGSize(width: 320, height: 200)
        )
        let laidOutFirst = layout[0]

        XCTAssertEqual(laidOutFirst.bounds.minX, first.bounds.minX)
        XCTAssertGreaterThan(laidOutFirst.bounds.width, first.bounds.width)
        XCTAssertLessThanOrEqual(laidOutFirst.bounds.maxX, second.bounds.minX - 4)
        XCTAssertEqual(laidOutFirst.lineLimit, 1)
    }

    func testTranslationLayoutKeepsTextInsideTheCanvasAtTheRightEdge() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "帮助",
            translatedText: "A much longer translated label",
            bounds: CGRect(x: 280, y: 40, width: 30, height: 20),
            confidence: 0.9
        )

        let layout = ScreenshotTranslationLayout.apply(
            to: [block],
            canvasSize: CGSize(width: 320, height: 200)
        )
        let laidOutBlock = try XCTUnwrap(layout.first)

        XCTAssertLessThanOrEqual(laidOutBlock.bounds.maxX, 320)
        XCTAssertGreaterThan(laidOutBlock.fontSize, 0)
        XCTAssertGreaterThanOrEqual(laidOutBlock.lineLimit, 1)
    }

    func testTranslationLayoutWrapsVeryLongTextWhenVerticalSpaceIsAvailable() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "菜单",
            translatedText: "这是一个明显长于原文并且需要在译文区域内换行显示的菜单项",
            bounds: CGRect(x: 100, y: 40, width: 20, height: 20),
            confidence: 0.9
        )

        let layout = ScreenshotTranslationLayout.apply(
            to: [block],
            canvasSize: CGSize(width: 320, height: 200)
        )
        let laidOutBlock = try XCTUnwrap(layout.first)

        XCTAssertGreaterThan(laidOutBlock.lineLimit, 1)
        XCTAssertGreaterThan(laidOutBlock.bounds.height, block.bounds.height)
        XCTAssertLessThanOrEqual(laidOutBlock.bounds.maxY, 200)
    }

    func testTranslationLayoutUsesOriginalLineHeightForMergedParagraphs() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "A wrapped paragraph",
            translatedText: "这是一段很长的译文，用来验证合并后的段落仍然按照原始单行字号排版，而不是按照整段高度放大字体。",
            bounds: CGRect(x: 40, y: 40, width: 220, height: 96),
            confidence: 0.9,
            sourceLineHeight: 20
        )

        let layout = ScreenshotTranslationLayout.apply(
            to: [block],
            canvasSize: CGSize(width: 320, height: 200)
        )
        let laidOutBlock = try XCTUnwrap(layout.first)

        XCTAssertLessThanOrEqual(laidOutBlock.fontSize, 18)
        XCTAssertGreaterThan(laidOutBlock.lineLimit, 1)
    }

    func testTranslationLayoutStaysInsideTheActualTranslationRegion() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "Edge",
            translatedText: "这是一个很长的译文，必须限制在选区内部",
            bounds: CGRect(x: 180, y: 90, width: 24, height: 20),
            confidence: 0.9
        )
        let region = CGRect(x: 40, y: 30, width: 180, height: 100)

        let laidOut = try XCTUnwrap(
            ScreenshotTranslationLayout.apply(
                to: [block],
                canvasSize: CGSize(width: 320, height: 200),
                translationRegion: region
            ).first
        )

        XCTAssertGreaterThanOrEqual(laidOut.bounds.minX, region.minX)
        XCTAssertGreaterThanOrEqual(laidOut.bounds.minY, region.minY)
        XCTAssertLessThanOrEqual(laidOut.bounds.maxX, region.maxX)
        XCTAssertLessThanOrEqual(laidOut.bounds.maxY, region.maxY)
        XCTAssertFalse(laidOut.displayLines.isEmpty)
    }

    func testTranslationLayoutPreservesSourceLineCountAsTheMinimumDisplayLimit() throws {
        let sourceLines = [
            ScreenshotTranslationLine(
                text: "第一行",
                bounds: CGRect(x: 40, y: 40, width: 180, height: 20),
                lineHeight: 20
            ),
            ScreenshotTranslationLine(
                text: "第二行",
                bounds: CGRect(x: 40, y: 64, width: 180, height: 20),
                lineHeight: 20
            ),
            ScreenshotTranslationLine(
                text: "第三行",
                bounds: CGRect(x: 40, y: 88, width: 180, height: 20),
                lineHeight: 20
            )
        ]
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "第一行 第二行 第三行",
            translatedText: "第一段译文",
            bounds: CGRect(x: 40, y: 40, width: 180, height: 68),
            confidence: 0.9,
            sourceLineHeight: 20,
            sourceLines: sourceLines
        )

        let laidOut = try XCTUnwrap(
            ScreenshotTranslationLayout.apply(
                to: [block],
                canvasSize: CGSize(width: 320, height: 200)
            ).first
        )

        XCTAssertEqual(laidOut.sourceLines.count, 3)
        XCTAssertGreaterThanOrEqual(laidOut.lineLimit, 3)
        XCTAssertEqual(laidOut.displayLines.count, 3)
        XCTAssertEqual(laidOut.displayLineBounds.count, 3)
        XCTAssertEqual(laidOut.displayLineBounds[0].minY, sourceLines[0].bounds.minY)
        XCTAssertEqual(laidOut.displayLineBounds[1].minY, sourceLines[1].bounds.minY)
        XCTAssertEqual(laidOut.displayLineBounds[2].minY, sourceLines[2].bounds.minY)
    }

    func testSharedTextLayoutKeepsGraphemeClustersTogether() {
        let text = "👩‍💻 设置窗口"
        let lines = ScreenshotTranslationTextLayout.wrappedLines(
            text,
            fontSize: 16,
            maximumWidth: 42
        )

        XCTAssertEqual(lines.joined(separator: "").replacingOccurrences(of: " ", with: ""), "👩‍💻设置窗口")
        XCTAssertTrue(lines.allSatisfy { !$0.contains("\u{200D}") || $0.contains("👩‍💻") })
    }

    func testOCRParagraphMergingJoinsWrappedLinesIntoOneTranslationUnit() {
        let firstLine = ScreenshotOCRBlock(
            id: UUID(),
            text: "We've all been there. Ending up with a worse exam result than you",
            normalizedBounds: CGRect(x: 0.10, y: 0.20, width: 0.76, height: 0.04),
            confidence: 0.9
        )
        let secondLine = ScreenshotOCRBlock(
            id: UUID(),
            text: "had hoped for or expected, a friend cancelling a plan you were really",
            normalizedBounds: CGRect(x: 0.10, y: 0.245, width: 0.77, height: 0.04),
            confidence: 0.9
        )
        let thirdLine = ScreenshotOCRBlock(
            id: UUID(),
            text: "looking forward to, or your favourite sports team losing a game.",
            normalizedBounds: CGRect(x: 0.10, y: 0.29, width: 0.72, height: 0.04),
            confidence: 0.9
        )

        let paragraphs = ScreenshotTranslationService.mergedParagraphBlocks(
            from: [thirdLine, firstLine, secondLine]
        )

        XCTAssertEqual(paragraphs.count, 1)
        XCTAssertEqual(
            paragraphs.first?.text,
            "We've all been there. Ending up with a worse exam result than you " +
                "had hoped for or expected, a friend cancelling a plan you were really " +
                "looking forward to, or your favourite sports team losing a game."
        )
        XCTAssertEqual(paragraphs.first?.normalizedBounds.minY, firstLine.normalizedBounds.minY)
        XCTAssertEqual(paragraphs.first?.normalizedBounds.maxY, thirdLine.normalizedBounds.maxY)
        XCTAssertEqual(paragraphs.first?.sourceLines.map(\.text), [
            firstLine.text,
            secondLine.text,
            thirdLine.text
        ])
    }

    func testOCRParagraphMergingKeepsCompactAdjacentRowsIndependentWithoutListMarkers() {
        let file = ScreenshotOCRBlock(
            id: UUID(),
            text: "File",
            normalizedBounds: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.04),
            confidence: 0.9
        )
        let edit = ScreenshotOCRBlock(
            id: UUID(),
            text: "Edit",
            normalizedBounds: CGRect(x: 0.10, y: 0.245, width: 0.20, height: 0.04),
            confidence: 0.9
        )

        let rows = ScreenshotTranslationService.mergedParagraphBlocks(from: [edit, file])

        XCTAssertEqual(rows.map(\.text), ["File", "Edit"])
        XCTAssertEqual(rows.map(\.sourceLines.count), [1, 1])
    }

    func testOCRParagraphMergingKeepsSeparatedRowsAndListItemsIndependent() {
        let first = ScreenshotOCRBlock(
            id: UUID(),
            text: "1. Settings",
            normalizedBounds: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.04),
            confidence: 0.9
        )
        let second = ScreenshotOCRBlock(
            id: UUID(),
            text: "2. Account",
            normalizedBounds: CGRect(x: 0.10, y: 0.245, width: 0.20, height: 0.04),
            confidence: 0.9
        )
        let separated = ScreenshotOCRBlock(
            id: UUID(),
            text: "Help",
            normalizedBounds: CGRect(x: 0.10, y: 0.36, width: 0.20, height: 0.04),
            confidence: 0.9
        )

        let paragraphs = ScreenshotTranslationService.mergedParagraphBlocks(
            from: [separated, second, first]
        )

        XCTAssertEqual(paragraphs.map(\.text), ["1. Settings", "2. Account", "Help"])
    }
}
