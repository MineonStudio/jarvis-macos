import AppKit
@testable import Jarvis
import XCTest

final class ScreenshotTranslationTests: XCTestCase {
    func testTranslationLanguagesExposeStablePersistedValues() {
        XCTAssertEqual(
            ScreenshotTranslationLanguage.allCases.map(\.rawValue),
            ["中文", "English", "日本語", "한국어", "Français", "Español"]
        )
        XCTAssertEqual(
            ScreenshotTranslationLanguage(rawValue: "日本語"),
            .japanese
        )
    }

    func testTranslationStatesRemainEquatable() {
        XCTAssertEqual(
            ScreenshotTranslationState.success("你好"),
            ScreenshotTranslationState.success("你好")
        )
        XCTAssertNotEqual(
            ScreenshotTranslationState.translating,
            ScreenshotTranslationState.failed("网络错误")
        )
    }

    func testTranslationAppearanceFollowsThemeContrast() throws {
        let lightText = try XCTUnwrap(
            ScreenshotTranslationRenderer
                .translationTextColor(isDarkMode: false)
                .usingColorSpace(.deviceRGB)
        )
        let darkText = try XCTUnwrap(
            ScreenshotTranslationRenderer
                .translationTextColor(isDarkMode: true)
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertEqual(lightText.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(lightText.greenComponent, 1, accuracy: 0.001)
        XCTAssertEqual(lightText.blueComponent, 1, accuracy: 0.001)
        XCTAssertEqual(darkText.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(darkText.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(darkText.blueComponent, 0, accuracy: 0.001)
        let lightMask = try XCTUnwrap(
            ScreenshotTranslationRenderer
                .translationMaskColor(isDarkMode: false)
                .usingColorSpace(.deviceRGB)
        )
        let darkMask = try XCTUnwrap(
            ScreenshotTranslationRenderer
                .translationMaskColor(isDarkMode: true)
                .usingColorSpace(.deviceRGB)
        )
        XCTAssertEqual(lightMask.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(darkMask.redComponent, 1, accuracy: 0.001)
    }

    func testScreenshotTranslationPromptRequiresVisionBoxes() {
        let prompt = ModelGateway.screenshotTranslationPrompt(targetLanguage: "English")

        XCTAssertTrue(prompt.contains("识别和翻译"))
        XCTAssertTrue(prompt.contains("English"))
        XCTAssertTrue(prompt.contains("左上角"))
        XCTAssertTrue(prompt.contains("完整行高"))
        XCTAssertTrue(prompt.contains("相邻行"))
        XCTAssertTrue(prompt.contains("改变 x、y、width 或 height"))
        XCTAssertTrue(prompt.contains("\"blocks\""))
    }

    func testCompactScreenshotTranslationPromptUsesPixelJSONLProtocol() {
        let prompt = ModelGateway.compactScreenshotTranslationPrompt(
            targetLanguage: "中文",
            imageSize: ScreenshotTranslationImageSize(width: 480, height: 374)
        )

        XCTAssertTrue(prompt.contains("480×374"))
        XCTAssertTrue(prompt.contains("JSONL"))
        XCTAssertTrue(prompt.contains("逐行"))
        XCTAssertTrue(prompt.contains("\"b\":[x,y,width,height]"))
        XCTAssertTrue(prompt.contains("整数"))
    }

    func testScreenshotTranslationInputUsesAdaptiveModelDetail() {
        XCTAssertEqual(
            ScreenshotTranslationInput.imageDetail(
                for: Data(repeating: 0, count: 1_999_999),
                maxDimension: 2399
            ),
            .high
        )
        XCTAssertEqual(
            ScreenshotTranslationInput.imageDetail(
                for: Data(repeating: 0, count: 2_000_000),
                maxDimension: 2399
            ),
            .low
        )
        XCTAssertEqual(
            ScreenshotTranslationInput.imageDetail(
                for: Data(),
                maxDimension: 2400
            ),
            .low
        )
    }

    func testScreenshotTranslationInputDownsamplesOnlyTheModelCopy() throws {
        let image = NSImage(size: NSSize(width: 2400, height: 1200))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 2400, height: 1200).fill()
        image.unlockFocus()

        let bitmap = try XCTUnwrap(try NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let input = try XCTUnwrap(ScreenshotTranslationInput.prepare(from: sourceData))
        let modelBitmap = try XCTUnwrap(NSBitmapImageRep(data: input.data))

        XCTAssertTrue(input.wasDownsampled)
        XCTAssertEqual(input.originalByteCount, sourceData.count)
        XCTAssertEqual(input.modelByteCount, input.data.count)
        XCTAssertLessThanOrEqual(max(modelBitmap.pixelsWide, modelBitmap.pixelsHigh), 2048)
        XCTAssertEqual(input.modelPixelSize.width, 2048)
        XCTAssertEqual(input.modelPixelSize.height, 1024)
        XCTAssertEqual(
            input.detail,
            ScreenshotTranslationInput.imageDetail(for: sourceData, maxDimension: 2400)
        )
        XCTAssertNotEqual(input.data, sourceData)
    }

    func testCompactScreenshotTranslationParserMapsPixelBoxesToNormalizedTopLeftBoxes() throws {
        let result = try XCTUnwrap(
            ModelGateway.parseCompactScreenshotTranslation(
                """
                {"b":[52,50,220,18],"t":"平台基础设施"}
                {"b":[100,200,120,40],"s":"Source","t":"译文"}
                """,
                imageSize: ScreenshotTranslationImageSize(width: 480, height: 374)
            )
        )

        XCTAssertEqual(result.blocks.count, 2)
        XCTAssertEqual(result.blocks[0].sourceText, "")
        XCTAssertEqual(result.blocks[0].translatedText, "平台基础设施")
        XCTAssertEqual(result.blocks[0].boundingBox.origin.x, 52.0 / 480.0, accuracy: 0.0001)
        XCTAssertEqual(result.blocks[0].boundingBox.origin.y, 50.0 / 374.0, accuracy: 0.0001)
        XCTAssertEqual(result.blocks[0].boundingBox.width, 220.0 / 480.0, accuracy: 0.0001)
        XCTAssertEqual(result.blocks[0].boundingBox.height, 18.0 / 374.0, accuracy: 0.0001)
        XCTAssertEqual(result.blocks[1].sourceText, "Source")
    }

    func testCompactScreenshotTranslationParserRejectsInvalidPixelBoxes() {
        let imageSize = ScreenshotTranslationImageSize(width: 480, height: 374)

        XCTAssertNil(
            ModelGateway.parseCompactScreenshotTranslationLine(
                "{\"b\":[450,50,40,18],\"t\":\"超出右边界\"}",
                imageSize: imageSize
            )
        )
        XCTAssertNil(
            ModelGateway.parseCompactScreenshotTranslationLine(
                "{\"b\":[52,50,220.5,18],\"t\":\"非整数框\"}",
                imageSize: imageSize
            )
        )
        XCTAssertNil(
            ModelGateway.parseCompactScreenshotTranslationLine(
                "{\"b\":[52,50,220,18],\"t\":\"   \"}",
                imageSize: imageSize
            )
        )
    }

    func testScreenshotTranslationParserPreservesSourceAndTranslationBoxes() throws {
        let response = """
        ```json
        {
          "blocks": [
            {
              "source": "Small red text",
              "translation": "小号红色文字",
              "box": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.08}
            },
            {
              "source": "Large blue text",
              "translation": "大号蓝色文字\\n第二行",
              "box": {"x": 0.2, "y": 0.65, "width": 0.5, "height": 0.2}
            }
          ]
        }
        ```
        """

        let result = try XCTUnwrap(ModelGateway.parseScreenshotTranslation(response))
        XCTAssertEqual(
            result.blocks.map(\.translatedText),
            ["小号红色文字", "大号蓝色文字\n第二行"]
        )
        XCTAssertEqual(result.blocks[0].sourceText, "Small red text")
        XCTAssertEqual(
            result.blocks[0].boundingBox,
            CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08)
        )
    }

    func testScreenshotTranslationParserRejectsInvalidNormalizedBoxes() {
        let response = """
        {"blocks":[{"source":"原文","translation":"译文","box":{"x":0.8,"y":0.2,"width":0.4,"height":0.1}}]}
        """

        XCTAssertNil(ModelGateway.parseScreenshotTranslation(response))
        XCTAssertNil(ModelGateway.parseScreenshotTranslation("统一译文"))
    }

    func testTranslationFontSizeFollowsSourceLineHeight() {
        let smallSource = ScreenshotTranslationRenderer.estimatedSourceFontSize(forLineHeight: 16)
        let largeSource = ScreenshotTranslationRenderer.estimatedSourceFontSize(forLineHeight: 40)

        XCTAssertGreaterThan(smallSource, 0)
        XCTAssertGreaterThan(largeSource, smallSource)
    }

    func testTranslationFontSizeAlsoConsidersSourceTextWidth() {
        let sourceRect = CGRect(x: 0, y: 0, width: 120, height: 32)
        let shortText = ScreenshotTranslationRenderer.estimatedSourceFontSize(
            for: "短",
            in: sourceRect
        )
        let longText = ScreenshotTranslationRenderer.estimatedSourceFontSize(
            for: "这是一段需要占用更大宽度的原文",
            in: sourceRect
        )

        XCTAssertGreaterThan(shortText, longText)
    }

    func testVisionBoxCoordinatesMapFromTopLeftWithoutVerticalOffset() {
        let pixelRect = ScreenshotTranslationRenderer.pixelRect(
            forTopLeftNormalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08),
            imageSize: CGSize(width: 1000, height: 500)
        )

        XCTAssertEqual(pixelRect.minX, 100, accuracy: 0.001)
        XCTAssertEqual(pixelRect.minY, 360, accuracy: 0.001)
        XCTAssertEqual(pixelRect.width, 300, accuracy: 0.001)
        XCTAssertEqual(pixelRect.height, 40, accuracy: 0.001)
    }

    func testReplacementRectAddsCoveragePaddingWithoutChangingTheSourceAnchor() {
        let sourceRect = ScreenshotTranslationRenderer.pixelRect(
            forTopLeftNormalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08),
            imageSize: CGSize(width: 1000, height: 500)
        )
        let replacementRect = ScreenshotTranslationRenderer.replacementRect(
            forTopLeftNormalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08),
            imageSize: CGSize(width: 1000, height: 500)
        )

        XCTAssertEqual(replacementRect.minX, sourceRect.minX - 6, accuracy: 0.001)
        XCTAssertEqual(replacementRect.minY, sourceRect.minY - 4, accuracy: 0.001)
        XCTAssertEqual(replacementRect.midX, sourceRect.midX, accuracy: 0.001)
        XCTAssertEqual(replacementRect.midY, sourceRect.midY, accuracy: 0.001)
    }

    func testTranslationTextRectAnchorsToTheSourceLineTop() {
        let sourceRect = CGRect(x: 10, y: 20, width: 120, height: 24)
        let textRect = ScreenshotTranslationRenderer.translationTextRect(
            in: sourceRect,
            measuredHeight: 14
        )

        XCTAssertEqual(textRect.minX, sourceRect.minX, accuracy: 0.001)
        XCTAssertEqual(textRect.maxY, sourceRect.maxY, accuracy: 0.001)
        XCTAssertEqual(textRect.height, 14, accuracy: 0.001)
    }

    func testTranslationRendererCreatesPNGForAlignedBlocks() throws {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let bitmap = try XCTUnwrap(try NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let block = ScreenshotTranslationBlock(
            sourceText: "原文",
            translatedText: "Translation",
            boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.2)
        )

        let output = ScreenshotTranslationRenderer.render(
            sourceData: sourceData,
            blocks: [block]
        )

        XCTAssertNotNil(output)
        XCTAssertNotNil(output.flatMap(NSImage.init(data:)))
        let outputBitmap = output.flatMap(NSBitmapImageRep.init(data:))
        XCTAssertGreaterThan(outputBitmap?.colorAt(x: 5, y: 5)?.alphaComponent ?? 0, 0.99)
    }

    func testTranslationRendererUsesOnlyOneOpaqueMaskLayer() throws {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let bitmap = try XCTUnwrap(try NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let output = try XCTUnwrap(
            ScreenshotTranslationRenderer.render(
                sourceData: sourceData,
                blocks: [ScreenshotTranslationBlock(
                    sourceText: "原文",
                    translatedText: "译",
                    boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.2)
                )]
            )
        )
        let outputBitmap = try XCTUnwrap(NSBitmapImageRep(data: output))
        let background = try XCTUnwrap(outputBitmap.colorAt(x: 8, y: 30)?.usingColorSpace(.deviceRGB))

        XCTAssertLessThan(background.redComponent, 0.05)
        XCTAssertLessThan(background.greenComponent, 0.05)
        XCTAssertLessThan(background.blueComponent, 0.05)
    }

    func testTranslationRendererRejectsEmptyTranslationBlocks() throws {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let bitmap = try XCTUnwrap(try NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertNil(
            ScreenshotTranslationRenderer.render(
                sourceData: sourceData,
                blocks: []
            )
        )
    }

    func testTranslationTextColorMatchesSourceForegroundColor() throws {
        let image = NSImage(size: NSSize(width: 300, height: 120))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 300, height: 120).fill()
        let sourceColor = NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.86, alpha: 1)
        sourceColor.set()
        ("Source" as NSString).draw(
            at: NSPoint(x: 40, y: 42),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 28),
                .foregroundColor: sourceColor
            ]
        )
        image.unlockFocus()

        let bitmap = try XCTUnwrap(try NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        let sourceData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let color = ScreenshotTranslationRenderer.estimatedSourceTextColor(
            for: sourceData,
            boundingBox: CGRect(x: 0.08, y: 0.25, width: 0.5, height: 0.5)
        )
        let rgb = try XCTUnwrap(color.usingColorSpace(.deviceRGB))

        XCTAssertGreaterThan(rgb.blueComponent, rgb.redComponent)
        XCTAssertGreaterThan(rgb.blueComponent, rgb.greenComponent)
        XCTAssertGreaterThan(rgb.greenComponent, 0.2)
    }
}
