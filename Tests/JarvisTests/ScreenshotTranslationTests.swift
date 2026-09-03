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

    func testAPIConnectionTestRejectsMissingConfigurationBeforeNetworkCall() async {
        do {
            try await OpenAICompatibleAPIClient().testConnection(
                configuration: AIAPIConfiguration(endpoint: "", model: "", apiKey: "")
            )
            XCTFail("Expected missing configuration error")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .missingConfiguration)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIConnectionTestRejectsMalformedEndpointBeforeNetworkCall() async {
        do {
            try await OpenAICompatibleAPIClient().testConnection(
                configuration: AIAPIConfiguration(
                    endpoint: "not an endpoint",
                    model: "test-model",
                    apiKey: "test-key"
                )
            )
            XCTFail("Expected invalid endpoint error")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .invalidEndpoint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await OpenAICompatibleAPIClient().testConnection(
                configuration: AIAPIConfiguration(
                    endpoint: "http://api.openai.com/v1",
                    model: "test-model",
                    apiKey: "test-key"
                )
            )
            XCTFail("Expected invalid endpoint error")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .invalidEndpoint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIConnectionTestRejectsEnvelopeWithoutTextContent() throws {
        let response: [String: Any] = [
            "choices": [[
                "message": [
                    "role": "assistant",
                    "content": NSNull()
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: response)

        XCTAssertThrowsError(try OpenAICompatibleAPIClient.validateConnectionEnvelope(from: data))
    }

    func testNormalizedEndpointRequiresHTTPSAndFillsOpenAICompletionsPath() {
        XCTAssertNil(OpenAICompatibleAPIClient.normalizedEndpointURL(from: "http://api.openai.com/v1"))
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "https://api.openai.com")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "https://api.openai.com/v1")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "https://example.com/v1/chat/completions")?.absoluteString,
            "https://example.com/v1/chat/completions"
        )
    }

    func testJSONContentExtractorAcceptsFencedObjectsAndRejectsProse() {
        let fenced = """
        ```json
        {"quote":"hello"}
        ```
        """
        let data = OpenAICompatibleAPIClient.jsonData(fromModelContent: fenced)
        XCTAssertNotNil(data)
        XCTAssertNil(OpenAICompatibleAPIClient.jsonData(fromModelContent: "not json"))
    }

    func testTranslationSkipsPunctuationAndNumberOnlyFragments() {
        XCTAssertFalse(ScreenshotTranslationService.needsTranslation("12:30"))
        XCTAssertFalse(ScreenshotTranslationService.needsTranslation("100%"))
        XCTAssertFalse(ScreenshotTranslationService.needsTranslation("—"))
        XCTAssertTrue(ScreenshotTranslationService.needsTranslation("Settings"))
        XCTAssertTrue(ScreenshotTranslationService.needsTranslation("设置"))
    }

    func testClassificationSkipsNumbersAndTextAlreadyInTheTargetLanguage() {
        let number = ScreenshotOCRBlock(
            id: UUID(),
            text: "12:30",
            normalizedBounds: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.04),
            confidence: 0.9
        )
        let chinese = ScreenshotOCRBlock(
            id: UUID(),
            text: "请打开设置窗口并选择你偏好的语言",
            normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.4, height: 0.04),
            confidence: 0.9
        )
        let english = ScreenshotOCRBlock(
            id: UUID(),
            text: "Please open the Settings window and choose your preferred language.",
            normalizedBounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.04),
            confidence: 0.9
        )

        let plan = ScreenshotTranslationService.classify(
            [number, chinese, english],
            targetLanguage: .simplifiedChinese
        )

        XCTAssertEqual(plan.translatableCount, 1)
        XCTAssertEqual(plan.groups.count, 1)
        XCTAssertEqual(plan.groups[0].blocks.map(\.text), [english.text])
        XCTAssertEqual(
            plan.groups[0].source?.languageCode?.identifier,
            "en"
        )
    }

    func testClassificationGroupsMixedSourceLanguagesSeparately() {
        let english = ScreenshotOCRBlock(
            id: UUID(),
            text: "Please open the Settings window and choose your preferred language.",
            normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.04),
            confidence: 0.9
        )
        let japanese = ScreenshotOCRBlock(
            id: UUID(),
            text: "設定ウィンドウを開いて、希望する言語を選択してください。",
            normalizedBounds: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.04),
            confidence: 0.9
        )

        let plan = ScreenshotTranslationService.classify(
            [english, japanese],
            targetLanguage: .simplifiedChinese
        )

        XCTAssertEqual(plan.groups.count, 2)
        let identifiers = Set(plan.groups.compactMap { $0.source?.languageCode?.identifier })
        XCTAssertEqual(identifiers, ["en", "ja"])
    }

    func testLanguagePackTargetsOrderMatchesSettingsList() {
        XCTAssertEqual(
            ScreenshotTranslationLanguage.packTargets.map(\.rawValue),
            ["zh-Hans", "en", "ja", "ko", "es"]
        )
    }

    func testLanguagePackProbesUseChineseEnglishRepresentativePairs() {
        // 目标为中文时用英语作源语言探测
        XCTAssertEqual(
            ScreenshotLanguagePackProbe(target: .simplifiedChinese).source,
            .english
        )
        XCTAssertEqual(
            ScreenshotLanguagePackProbe(target: .traditionalChinese).source,
            .english
        )
        // 其余目标以简体中文为源语言探测
        for target in [ScreenshotTranslationLanguage.english, .japanese, .korean, .spanish] {
            let probe = ScreenshotLanguagePackProbe(target: target)
            XCTAssertEqual(probe.source, .simplifiedChinese)
            XCTAssertFalse(probe.sampleText.isEmpty)
        }
    }

    func testTargetLanguageMatchingTreatsChineseScriptsSeparately() {
        XCTAssertTrue(
            ScreenshotTranslationLanguage.simplifiedChinese.matches(
                Locale.Language(identifier: "zh-Hans")
            )
        )
        XCTAssertFalse(
            ScreenshotTranslationLanguage.simplifiedChinese.matches(
                Locale.Language(identifier: "zh-Hant")
            )
        )
        XCTAssertTrue(
            ScreenshotTranslationLanguage.english.matches(
                Locale.Language(identifier: "en-US")
            )
        )
    }

    func testOCRLineMergingJoinsAdjacentFragmentsOnTheSameRow() {
        let left = ScreenshotOCRBlock(
            id: UUID(),
            text: "Hello",
            normalizedBounds: CGRect(x: 0.10, y: 0.20, width: 0.12, height: 0.04),
            confidence: 0.9
        )
        let right = ScreenshotOCRBlock(
            id: UUID(),
            text: "world",
            normalizedBounds: CGRect(x: 0.24, y: 0.20, width: 0.12, height: 0.04),
            confidence: 0.8
        )
        let nextLine = ScreenshotOCRBlock(
            id: UUID(),
            text: "Next",
            normalizedBounds: CGRect(x: 0.10, y: 0.40, width: 0.12, height: 0.04),
            confidence: 0.9
        )

        let merged = ScreenshotTranslationService.mergedLineBlocks(from: [right, nextLine, left])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].text, "Hello world")
        XCTAssertEqual(merged[1].text, "Next")
    }

    func testTranslationBatchesSplitOversizedOCRPayloads() {
        let small = (0 ..< 3).map { AITranslationInput(id: "\($0)", text: "hi") }
        XCTAssertEqual(ScreenshotTranslationService.translationBatches(from: small).count, 1)

        let large = [
            AITranslationInput(id: "a", text: String(repeating: "字", count: 4000)),
            AITranslationInput(id: "b", text: String(repeating: "字", count: 4000))
        ]
        XCTAssertEqual(ScreenshotTranslationService.translationBatches(from: large).count, 2)
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

    func testTranslationServiceDelegatesTextToTheAPIAndKeepsVisionBounds() async throws {
        let id = UUID()
        let blocks = [ScreenshotOCRBlock(
            id: id,
            text: "Hello",
            normalizedBounds: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1),
            confidence: 0.95
        )]
        let service = ScreenshotTranslationService(apiClient: StubTranslationAPI())
        let configuration = ScreenshotTranslationConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key",
            targetLanguage: .simplifiedChinese
        )

        let result = try await service.translate(
            blocks,
            targetLanguage: .simplifiedChinese,
            configuration: configuration
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].translatedText, "你好")
        XCTAssertEqual(result[0].normalizedBounds, blocks[0].normalizedBounds)
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

private struct StubTranslationAPI: AITranslationAPI {
    func translate(
        _ items: [AITranslationInput],
        targetLanguage _: String,
        configuration _: AIAPIConfiguration
    ) async throws -> [AITranslationOutput] {
        items.map { AITranslationOutput(id: $0.id, translation: "你好") }
    }
}
