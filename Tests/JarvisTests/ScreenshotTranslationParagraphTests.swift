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

    func testTranslationLayoutFlowsDisplayLinesAndStillCoversTheSourceBlock() throws {
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
            translatedText: "三行译文",
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

        // 译文比原文短时不再补齐空行，整段连续排版。
        XCTAssertEqual(laidOut.displayLines, ["三行译文"])
        XCTAssertEqual(laidOut.displayLineBounds.count, 1)
        // 盒子仍然覆盖整块原文，原文不会被露出来。
        XCTAssertGreaterThanOrEqual(
            laidOut.bounds.maxY,
            sourceLines.map(\.bounds.maxY).max() ?? 0
        )
        XCTAssertGreaterThanOrEqual(laidOut.displayLineBounds[0].minY, laidOut.bounds.minY)
        XCTAssertLessThanOrEqual(laidOut.displayLineBounds[0].maxY, laidOut.bounds.maxY)
    }

    func testTranslationLayoutKeepsDisplayLinesSequentialWithoutGaps() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "A wrapped sentence",
            translatedText: "这是一段需要折行的译文，用来验证每一行都紧挨着上一行，中间不会出现空行。",
            bounds: CGRect(x: 30, y: 30, width: 120, height: 48),
            confidence: 0.9,
            sourceLineHeight: 16
        )

        let laidOut = try XCTUnwrap(
            ScreenshotTranslationLayout.apply(
                to: [block],
                canvasSize: CGSize(width: 400, height: 300)
            ).first
        )

        XCTAssertGreaterThan(laidOut.displayLines.count, 1)
        XCTAssertTrue(laidOut.displayLines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })

        let lineHeight = ScreenshotTranslationTextLayout.measuredLineHeight(fontSize: laidOut.fontSize)
        for index in 1 ..< laidOut.displayLineBounds.count {
            XCTAssertEqual(
                laidOut.displayLineBounds[index].minY,
                laidOut.displayLineBounds[index - 1].minY + lineHeight,
                accuracy: 0.01
            )
        }
    }

    func testTranslationLayoutWrapsLatinWordsInsteadOfSplittingThem() {
        let text = "并击退 illagers 的攻击，然后回到 Minecraft 地牢"
        let lines = ScreenshotTranslationTextLayout.wrappedLines(
            text,
            fontSize: 16,
            maximumWidth: 120
        )

        XCTAssertGreaterThan(lines.count, 1)
        for word in ["illagers", "Minecraft"] {
            XCTAssertTrue(
                lines.contains { $0.contains(word) },
                "拉丁词被拆开了：\(lines)"
            )
        }
        XCTAssertEqual(
            lines.joined().replacingOccurrences(of: " ", with: ""),
            text.replacingOccurrences(of: " ", with: "")
        )
    }

    func testTranslationFontSizeFallsBackToBlockHeightWhenLineHeightIsDegenerate() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "FIGHT BACK THE BLUE CREEPER",
            translatedText: "反击蓝色爬行者",
            bounds: CGRect(x: 8, y: 8, width: 500, height: 48),
            confidence: 0.9,
            sourceLineHeight: 8,
            sourceLines: [
                ScreenshotTranslationLine(
                    text: "FIGHT BACK THE BLUE CREEPER",
                    bounds: CGRect(x: 8, y: 8, width: 500, height: 48),
                    lineHeight: 8
                )
            ]
        )

        let laidOut = try XCTUnwrap(
            ScreenshotTranslationLayout.apply(
                to: [block],
                canvasSize: CGSize(width: 1000, height: 500)
            ).first
        )

        // 单行块的框高是这一行本身：行高明显偏小时按框高兜底，不再渲染成 6pt 小字。
        XCTAssertGreaterThan(laidOut.fontSize, 20)
    }

    func testTranslationLayoutWrapsInsteadOfShrinkingPastTheFloor() throws {
        let block = ScreenshotTranslationRenderBlock(
            id: UUID(),
            sourceText: "Settings",
            translatedText: "打开系统设置窗口并选择你偏好的语言、输入法与显示方式，然后重新启动应用生效",
            bounds: CGRect(x: 40, y: 40, width: 90, height: 20),
            confidence: 0.9,
            sourceLineHeight: 20,
            sourceLines: [
                ScreenshotTranslationLine(
                    text: "Settings",
                    bounds: CGRect(x: 40, y: 40, width: 90, height: 20),
                    lineHeight: 20
                )
            ]
        )

        let laidOut = try XCTUnwrap(
            ScreenshotTranslationLayout.apply(
                to: [block],
                canvasSize: CGSize(width: 400, height: 300)
            ).first
        )

        // 需要缩小超过 40% 时改为折行，保持和相邻块一致的字号。
        XCTAssertEqual(laidOut.fontSize, 18, accuracy: 0.01)
        XCTAssertGreaterThan(laidOut.displayLines.count, 1)
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

    func testOCRParagraphMergingRejectsABlankLineWiderThanTheParagraphsOwnLineGap() {
        let firstLine = ScreenshotOCRBlock(
            id: UUID(),
            text: "Starting September 17, heroes across the world must band together",
            normalizedBounds: CGRect(x: 0.008, y: 0.1224, width: 0.98, height: 0.045),
            confidence: 0.9
        )
        let secondLine = ScreenshotOCRBlock(
            id: UUID(),
            text: "online, in Minecraft, or at Tokyo Game Show itself - to defeat it",
            normalizedBounds: CGRect(x: 0.008, y: 0.1744, width: 0.85, height: 0.045),
            confidence: 0.9
        )
        // 段内行距 0.007，这一行与上一行的间距是 0.02：远大于段内行距，属于段间空行。
        let nextParagraph = ScreenshotOCRBlock(
            id: UUID(),
            text: "Visitors attending Tokyo Game Show must journey to the booth",
            normalizedBounds: CGRect(x: 0.008, y: 0.2394, width: 0.98, height: 0.045),
            confidence: 0.9
        )

        let paragraphs = ScreenshotTranslationService.mergedParagraphBlocks(
            from: [nextParagraph, secondLine, firstLine]
        )

        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].sourceLines.count, 2)
        XCTAssertEqual(paragraphs[1].sourceLines.count, 1)
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
