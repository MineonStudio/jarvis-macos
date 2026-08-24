import Foundation

extension AppModel {
    func translateScreenshot() {
        guard let screenshotData = loadLatestScreenshotIfNeeded() else {
            showToast("请先截取一块屏幕区域")
            return
        }

        translateScreenshot(data: screenshotData)
    }

    func translateScreenshot(data: Data) {
        guard !data.isEmpty else {
            showToast("截图内容为空，无法翻译")
            return
        }

        let key = KeychainStore.shared.value(for: "jarvis.api-key") ?? ""
        guard !key.isEmpty else {
            selectedSection = .settings
            screenshotTranslationState = .failed("请先在设置中配置 API Key")
            screenshotTranslationProgress.isTranslating = false
            showToast("请先在设置中配置 API Key")
            return
        }

        translationTask?.cancel()
        let requestID = UUID()
        translationRequestID = requestID
        translationSourceData = data
        latestTranslation = ""
        screenshotTranslationState = .translating
        screenshotTranslationProgress.isTranslating = true
        statusMessage = "正在让大模型识别并翻译截图…"

        translationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await modelGateway.translateScreenshot(
                    imageData: data,
                    targetLanguage: targetLanguage.rawValue,
                    configuration: modelConfiguration,
                    apiKey: key
                )
                try Task.checkCancellation()
                guard translationRequestID == requestID else { return }

                translationTask = nil
                latestTranslation = result.translatedText
                guard let translatedData = ScreenshotTranslationRenderer.render(
                    sourceData: data,
                    blocks: result.blocks,
                    isDarkMode: themePreference.resolvedColorScheme(system: systemColorScheme) == .dark
                ), screenshotController.applyTranslatedScreenshot(translatedData)
                else {
                    screenshotTranslationState = .failed("无法生成翻译后的截图")
                    screenshotTranslationProgress.isTranslating = false
                    showToast("无法生成翻译后的截图")
                    return
                }
                screenshotTranslationState = .success(latestTranslation)
                screenshotTranslationProgress.isTranslating = false
                showToast("翻译完成，已替换原文区域")
            } catch is CancellationError {
                return
            } catch {
                guard translationRequestID == requestID else { return }
                let message = error.localizedDescription
                screenshotTranslationState = .failed(message)
                screenshotTranslationProgress.isTranslating = false
                showToast("翻译失败：\(error.localizedDescription)")
            }
        }
    }

    func translateCurrentScreenshot() {
        let data = screenshotController.currentEditingPNGData()
            ?? translationSourceData
            ?? loadLatestScreenshotIfNeeded()
        guard let data else {
            showToast("请先截取一块屏幕区域")
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
        latestTranslation = ""
        screenshotTranslationState = .idle
        screenshotTranslationProgress.isTranslating = false
    }
}
