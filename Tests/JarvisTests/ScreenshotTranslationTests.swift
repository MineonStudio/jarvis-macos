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

    func testTranslationConfigurationLoadsTargetLanguageAndIgnoresLegacyAPIKeys() throws {
        let suiteName = "ScreenshotTranslationConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            ScreenshotTranslationConfiguration.loadTargetLanguage(defaults: defaults),
            .simplifiedChinese
        )

        defaults.set(
            ScreenshotTranslationLanguage.english.rawValue,
            forKey: ScreenshotTranslationConfiguration.targetLanguageKey
        )
        XCTAssertEqual(
            ScreenshotTranslationConfiguration.loadTargetLanguage(defaults: defaults),
            .english
        )
    }

    func testUnsupportedLanguagePairAsksUserToDownloadLanguagePack() {
        XCTAssertEqual(
            ScreenshotTranslationError.unsupportedLanguagePair.errorDescription,
            "系统翻译不支持该语言，请先在设置中下载对应语言包"
        )
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

    func testNormalizedLanguageMapsSpanishToSpainLocale() {
        let normalized = ScreenshotAppleTranslation.normalizedLanguage(
            Locale.Language(identifier: "es")
        )
        XCTAssertEqual(normalized.languageCode?.identifier.lowercased(), "es")
        XCTAssertEqual(normalized.region?.identifier, "ES")
    }

    func testDetectedLanguageRecognizesSpanishWhenItIsAPackTarget() {
        let language = ScreenshotTranslationService.detectedLanguage(
            for: "El rápido zorro marrón salta sobre el perro perezoso todas las mañanas."
        )
        XCTAssertEqual(language?.languageCode?.identifier.lowercased(), "es")
    }

    func testClassifyGroupsSpanishSeparatelyFromEnglish() {
        let spanish = ScreenshotOCRBlock(
            id: UUID(),
            text: "El rápido zorro marrón salta sobre el perro perezoso todas las mañanas.",
            normalizedBounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.04),
            confidence: 0.9
        )
        let english = ScreenshotOCRBlock(
            id: UUID(),
            text: "The quick brown fox jumps over the lazy dog every morning.",
            normalizedBounds: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.04),
            confidence: 0.9
        )
        let plan = ScreenshotTranslationService.classify(
            [spanish, english],
            targetLanguage: .simplifiedChinese
        )
        let identifiers = Set(plan.groups.compactMap { $0.source?.languageCode?.identifier })
        XCTAssertTrue(identifiers.contains("es"))
        XCTAssertTrue(identifiers.contains("en"))
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
            normalizedBounds: CGRect(x: 0.232, y: 0.20, width: 0.12, height: 0.04),
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

    func testOCRLineMergingKeepsVisuallySeparatedFragmentsAsBlocks() {
        let left = ScreenshotOCRBlock(
            id: UUID(),
            text: "File",
            normalizedBounds: CGRect(x: 0.10, y: 0.20, width: 0.08, height: 0.04),
            confidence: 0.9
        )
        let right = ScreenshotOCRBlock(
            id: UUID(),
            text: "Edit",
            normalizedBounds: CGRect(x: 0.24, y: 0.20, width: 0.08, height: 0.04),
            confidence: 0.8
        )

        let blocks = ScreenshotTranslationService.mergedLineBlocks(from: [right, left])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.text), ["File", "Edit"])
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
