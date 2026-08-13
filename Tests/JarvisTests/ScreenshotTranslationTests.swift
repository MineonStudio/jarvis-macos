import AppKit
import XCTest
@testable import Jarvis

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

    func testTranslationPromptPreservesFormattingRequirements() {
        let prompt = ModelGateway.translationPrompt(sourceText: "Hello\nWorld", targetLanguage: "English")

        XCTAssertTrue(prompt.contains("English"))
        XCTAssertTrue(prompt.contains("段落、列表和换行"))
        XCTAssertTrue(prompt.contains("只返回完整译文"))
        XCTAssertTrue(prompt.contains("Hello\nWorld"))
        XCTAssertFalse(prompt.contains("image_url"))
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

    func testTranslationRendererCreatesPNGForAlignedBlocks() {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let sourceData = bitmap.representation(using: .png, properties: [:])!
        let ocrResult = ScreenshotOCRResult(
            text: "原文",
            blocks: [ScreenshotOCRBlock(text: "原文", boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.2))]
        )

        let output = ScreenshotTranslationRenderer.render(
            sourceData: sourceData,
            ocrResult: ocrResult,
            translatedText: "Translation"
        )

        XCTAssertNotNil(output)
        XCTAssertNotNil(output.flatMap(NSImage.init(data:)))
        let outputBitmap = output.flatMap(NSBitmapImageRep.init(data:))
        XCTAssertGreaterThan(outputBitmap?.colorAt(x: 5, y: 5)?.alphaComponent ?? 0, 0.99)
    }

    func testTranslationTextColorMatchesSourceForegroundColor() {
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

        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let sourceData = bitmap.representation(using: .png, properties: [:])!
        let color = ScreenshotTranslationRenderer.estimatedSourceTextColor(
            for: sourceData,
            boundingBox: CGRect(x: 0.08, y: 0.25, width: 0.5, height: 0.5)
        )
        let rgb = color.usingColorSpace(.deviceRGB)!

        XCTAssertGreaterThan(rgb.blueComponent, rgb.redComponent)
        XCTAssertGreaterThan(rgb.blueComponent, rgb.greenComponent)
        XCTAssertGreaterThan(rgb.greenComponent, 0.2)
    }
}
