import AppKit
@testable import Jarvis
import XCTest

final class ScreenshotTranslationTests: XCTestCase {
    func testTranslationGeometryMapsVisionBoundsIntoSelectedCanvasRect() {
        let selection = CGRect(x: 100, y: 80, width: 800, height: 500)
        let normalized = CGRect(x: 0.25, y: 0.1, width: 0.5, height: 0.2)

        XCTAssertEqual(
            ScreenshotTranslationGeometry.canvasBounds(for: normalized, in: selection),
            CGRect(x: 300, y: 130, width: 400, height: 100)
        )
    }

    func testTranslationStateOnlyReportsActiveWorkWhileRecognizingOrTranslating() {
        XCTAssertFalse(ScreenshotTranslationState.idle.isRunning)
        XCTAssertTrue(ScreenshotTranslationState.recognizing.isRunning)
        XCTAssertTrue(ScreenshotTranslationState.translating(completed: 1, total: 2).isRunning)
        XCTAssertFalse(ScreenshotTranslationState.completed(count: 2).isRunning)
        XCTAssertFalse(ScreenshotTranslationState.failed("失败").isRunning)
    }

    func testTranslationConfigurationRequiresAnAPIKey() {
        let missingKey = ScreenshotTranslationConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "",
            targetLanguage: .simplifiedChinese
        )
        let configured = ScreenshotTranslationConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key",
            targetLanguage: .english
        )

        XCTAssertFalse(missingKey.isConfigured)
        XCTAssertTrue(configured.isConfigured)
    }

    func testVisionOCRRejectsInvalidImageData() async {
        do {
            _ = try await ScreenshotTranslationService().recognizeText(in: Data([1, 2, 3]))
            XCTFail("Expected invalid image error")
        } catch let error as ScreenshotTranslationError {
            XCTAssertEqual(error, .invalidImage)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRenderPipelineIncludesTranslationLayer() throws {
        let image = NSImage(size: NSSize(width: 120, height: 80))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        image.unlockFocus()

        let request = ScreenshotRenderRequest(
            image: image,
            canvasSize: CGSize(width: 120, height: 80),
            pixelScale: 1,
            annotations: [],
            blurredImage: nil,
            pixelatedImage: nil,
            translations: [ScreenshotTranslationRenderBlock(
                id: UUID(),
                sourceText: "Hello",
                translatedText: "你好",
                bounds: CGRect(x: 10, y: 10, width: 70, height: 24),
                confidence: 0.98
            )],
            showsTranslation: true
        )

        let data = try XCTUnwrap(ScreenshotRenderPipeline().renderFullCanvas(request))
        XCTAssertNotNil(NSImage(data: data))
    }
}
