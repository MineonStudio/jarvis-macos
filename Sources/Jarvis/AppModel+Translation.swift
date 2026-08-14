import Foundation

extension AppModel {
    func translateScreenshot() {
        guard let screenshotData = latestScreenshotData else {
            statusMessage = "请先截取一块屏幕区域"
            return
        }

        translateScreenshot(data: screenshotData)
    }

    func translateScreenshot(data: Data) {
        guard !data.isEmpty else {
            statusMessage = "截图内容为空，无法翻译"
            return
        }

        let key = KeychainStore.shared.value(for: "jarvis.api-key") ?? ""
        guard !key.isEmpty else {
            selectedSection = .settings
            screenshotTranslationState = .failed("请先在设置中配置 API Key")
            screenshotTranslationProgress.isTranslating = false
            statusMessage = "请先在设置中配置 API Key"
            return
        }

        translationTask?.cancel()
        let requestID = UUID()
        translationRequestID = requestID
        translationSourceData = data
        translationOCRResult = nil
        latestTranslation = ""
        screenshotTranslationState = .translating
        screenshotTranslationProgress.isTranslating = true
        statusMessage = "正在本地识别截图文字…"

        translationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let ocrResult = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotTextRecognizer.recognize(in: data)
                }.value
                try Task.checkCancellation()
                guard translationRequestID == requestID else { return }

                translationTask = nil
                translationOCRResult = ocrResult
                translateRecognizedText(ocrResult, requestID: requestID)
            } catch is CancellationError {
                return
            } catch {
                guard translationRequestID == requestID else { return }
                let message = error.localizedDescription
                screenshotTranslationState = .failed(message)
                screenshotTranslationProgress.isTranslating = false
                statusMessage = "翻译失败：\(error.localizedDescription)"
            }
        }
    }

    private func translateRecognizedText(
        _ ocrResult: ScreenshotOCRResult,
        requestID: UUID
    ) {
        let sourceBlocks = ocrResult.blocks.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard sourceBlocks.count == ocrResult.blocks.count,
              !sourceBlocks.isEmpty,
              sourceBlocks.allSatisfy({ !$0.isEmpty })
        else {
            screenshotTranslationState = .failed("截图中未识别到文字")
            screenshotTranslationProgress.isTranslating = false
            statusMessage = "截图中未识别到文字"
            return
        }

        let key = KeychainStore.shared.value(for: "jarvis.api-key") ?? ""
        guard !key.isEmpty else {
            selectedSection = .settings
            screenshotTranslationState = .failed("请先在设置中配置 API Key")
            screenshotTranslationProgress.isTranslating = false
            statusMessage = "请先在设置中配置 API Key"
            return
        }

        translationTask?.cancel()
        screenshotTranslationState = .translating
        screenshotTranslationProgress.isTranslating = true
        statusMessage = "正在翻译识别出的文字…"

        translationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let translatedBlocks = try await modelGateway.translateBlocks(
                    sourceBlocks,
                    targetLanguage: targetLanguage.rawValue,
                    configuration: modelConfiguration,
                    apiKey: key
                )
                try Task.checkCancellation()
                guard translationRequestID == requestID else { return }
                translationTask = nil
                latestTranslation = translatedBlocks.joined(separator: "\n")
                guard let ocrResult = translationOCRResult,
                      let sourceData = translationSourceData,
                      let translatedData = ScreenshotTranslationRenderer.render(
                          sourceData: sourceData,
                          ocrResult: ocrResult,
                          translatedBlocks: translatedBlocks,
                          isDarkMode: themePreference.resolvedColorScheme(system: systemColorScheme) == .dark
                      ),
                      screenshotController.applyTranslatedScreenshot(translatedData)
                else {
                    screenshotTranslationState = .failed("无法生成翻译后的截图")
                    screenshotTranslationProgress.isTranslating = false
                    statusMessage = "无法生成翻译后的截图"
                    return
                }
                screenshotTranslationState = .success(latestTranslation)
                screenshotTranslationProgress.isTranslating = false
                statusMessage = "翻译完成，已替换原文区域"
            } catch is CancellationError {
                return
            } catch {
                guard translationRequestID == requestID else { return }
                translationTask = nil
                let message = error.localizedDescription
                screenshotTranslationState = .failed(message)
                screenshotTranslationProgress.isTranslating = false
                statusMessage = "翻译失败：\(error.localizedDescription)"
            }
        }
    }

    func translateCurrentScreenshot() {
        let data = screenshotController.currentEditingPNGData() ?? translationSourceData ?? latestScreenshotData
        guard let data else {
            statusMessage = "请先截取一块屏幕区域"
            return
        }
        translateScreenshot(data: translationSourceData ?? data)
    }

    func updateTranslationLanguage(_ language: ScreenshotTranslationLanguage) {
        targetLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: translationLanguageKey)
    }

    func loadTranslationLanguage() {
        guard let rawValue = UserDefaults.standard.string(forKey: translationLanguageKey),
              let language = ScreenshotTranslationLanguage(rawValue: rawValue)
        else {
            return
        }
        targetLanguage = language
    }

    func cancelScreenshotTranslation() {
        translationRequestID = UUID()
        translationTask?.cancel()
        translationTask = nil
        translationSourceData = nil
        translationOCRResult = nil
        latestTranslation = ""
        screenshotTranslationState = .idle
        screenshotTranslationProgress.isTranslating = false
    }
}
