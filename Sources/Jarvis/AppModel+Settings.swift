import AppKit
import Foundation
import SwiftUI

extension AppModel {
    // MARK: - Shared UI state

    func showToast(_ message: String) {
        statusMessage = message
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_400_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
            self?.toastDismissTask = nil
        }
    }

    func updateThemePreference(_ preference: JarvisTheme) {
        themePreference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: themePreferenceKey)
        JarvisDockIconController.shared.apply(
            theme: preference,
            isSystemDark: systemColorScheme == .dark
        )
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        let previousValue = launchAtLoginEnabled

        do {
            if enabled {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
        } catch {
            launchAtLoginEnabled = previousValue
            showToast(enabled ? "开机自启添加失败：\(error.localizedDescription)" : "开机自启关闭失败：\(error.localizedDescription)")
            return
        }

        launchAtLoginEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: JarvisLaunchAtLoginPreference.key)
        showToast(enabled ? "已开启开机自启" : "已关闭开机自启")
    }

    // MARK: - Shared AI API

    func loadAIAPISettings() {
        AIAPIConfiguration.migrateLegacyKeys()

        Task.detached { [weak self] in
            do {
                let apiKey = try AIAPIKeychain.shared.read()
                let provider = AIAPIConfiguration.load(resolvedAPIKey: apiKey)
                await self?.applyLoadedAIAPISettings(provider)
            } catch {
                let message = error.localizedDescription
                await self?.handleAIAPISettingsLoadFailure(message)
            }
        }
    }

    private func applyLoadedAIAPISettings(_ provider: AIAPIConfiguration) {
        applyProviderConfiguration(provider)
    }

    private func handleAIAPISettingsLoadFailure(_ message: String) {
        aiAPIKeyConfigured = false
        aiAPIKeyMask = ""
        aiSettingsLocked = false
        apiProvider = .openAI
        providerEndpoint = AIAPIConfiguration.defaultEndpoint
        providerModel = AIAPIConfiguration.defaultModel
        clearAIModels()
        showToast("读取 API Key 失败：\(message)")
    }

    @discardableResult
    func saveProviderSettings(
        provider: AIAPIProvider,
        baseURL: String,
        model: String,
        apiKey: String,
        announce: Bool = true
    ) -> Bool {
        do {
            let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveBaseURL = trimmedBaseURL.isEmpty
                ? provider.defaultBaseURL
                : trimmedBaseURL
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveModel = trimmedModel
            guard !effectiveModel.isEmpty else {
                showToast("请先刷新并选择模型")
                return false
            }

            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedAPIKey = try AIAPIKeychain.shared.read() ?? ""
            let resolvedAPIKey = trimmedAPIKey.isEmpty ? storedAPIKey : trimmedAPIKey
            guard !resolvedAPIKey.isEmpty else {
                showToast("请输入 API Key")
                return false
            }

            guard let endpoint = OpenAICompatibleAPIClient.normalizedEndpointURL(
                from: effectiveBaseURL,
                provider: provider
            )?
                .absoluteString
            else {
                showToast("接口地址需要是 HTTPS 地址")
                return false
            }
            let configuration = AIAPIConfiguration(
                endpoint: endpoint,
                model: effectiveModel,
                apiKey: resolvedAPIKey,
                providerID: provider.rawValue
            )
            try persistProviderConfiguration(
                configuration,
                writeKeychain: !trimmedAPIKey.isEmpty
            )
            if announce {
                showToast("API 配置已保存")
            }
            return true
        } catch {
            showToast("保存 API 配置失败：\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteAIAPIConfiguration() -> Bool {
        do {
            try AIAPIKeychain.shared.delete()
            AIAPIConfiguration.removeStoredConfiguration()

            providerEndpoint = AIAPIConfiguration.defaultEndpoint
            providerModel = AIAPIConfiguration.defaultModel
            apiProvider = .openAI
            clearAIModels()
            aiAPIKeyConfigured = false
            aiAPIKeyMask = ""
            aiSettingsLocked = false
            showToast("API 配置已删除")
            return true
        } catch {
            showToast("删除 API 配置失败：\(error.localizedDescription)")
            return false
        }
    }

    func editAIAPISettings() {
        aiSettingsLocked = false
    }

    func clearAIModels() {
        aiModelsRefreshTask?.cancel()
        aiModelsRefreshTask = nil
        availableAIModels = []
        aiModelsLoading = false
        aiModelsRefreshError = nil
    }

    func refreshAIModels(
        provider: AIAPIProvider,
        baseURL: String,
        selectedModel: String,
        apiKey: String
    ) {
        aiModelsRefreshTask?.cancel()
        aiModelsLoading = true
        aiModelsRefreshError = nil

        let enteredAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        aiModelsRefreshTask = Task.detached { [weak self] in
            do {
                let storedAPIKey = try AIAPIKeychain.shared.read() ?? ""
                let resolvedAPIKey = enteredAPIKey.isEmpty ? storedAPIKey : enteredAPIKey
                let configuration = AIAPIConfiguration(
                    endpoint: endpoint,
                    model: currentModel.isEmpty ? "model" : currentModel,
                    apiKey: resolvedAPIKey,
                    providerID: provider.rawValue
                )
                let models = try await OpenAICompatibleAPIClient().fetchModels(
                    configuration: configuration
                )
                guard !Task.isCancelled else { return }
                await self?.finishAIModelsRefresh(models)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.failAIModelsRefresh(error.localizedDescription)
            }
        }
    }

    private func finishAIModelsRefresh(_ models: [String]) {
        aiModelsRefreshTask = nil
        aiModelsLoading = false
        availableAIModels = models
        aiModelsRefreshError = nil
        showToast("已刷新 \(models.count) 个模型")
    }

    private func failAIModelsRefresh(_ message: String) {
        aiModelsRefreshTask = nil
        aiModelsLoading = false
        aiModelsRefreshError = message
    }

    private func persistProviderConfiguration(
        _ configuration: AIAPIConfiguration,
        writeKeychain: Bool
    ) throws {
        if writeKeychain, !configuration.apiKey.isEmpty {
            try AIAPIKeychain.shared.write(configuration.apiKey)
        }
        UserDefaults.standard.set(configuration.endpoint, forKey: AIAPIConfiguration.apiEndpointKey)
        UserDefaults.standard.set(configuration.model, forKey: AIAPIConfiguration.apiModelKey)
        UserDefaults.standard.removeObject(forKey: AIAPIConfiguration.apiNameKey)
        UserDefaults.standard.set(configuration.providerID, forKey: AIAPIConfiguration.apiProviderKey)
        applyProviderConfiguration(configuration)
    }

    private func applyProviderConfiguration(_ configuration: AIAPIConfiguration) {
        apiProvider = configuration.provider
        providerEndpoint = configuration.endpoint
        providerModel = configuration.model
        let hasAPIKey = !configuration.apiKey.isEmpty
        aiAPIKeyConfigured = hasAPIKey
        aiAPIKeyMask = hasAPIKey ? "••••••••" : ""
        aiSettingsLocked = hasAPIKey
    }

    func testAIAPIConnection(
        provider: AIAPIProvider = .custom,
        endpoint: String,
        model: String,
        apiKey: String
    ) async {
        guard !aiConnectionTesting else { return }

        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let storedAPIKey = try AIAPIKeychain.shared.read() ?? ""
            let configuration = AIAPIConfiguration(
                endpoint: trimmedEndpoint,
                model: trimmedModel,
                apiKey: trimmedAPIKey.isEmpty ? storedAPIKey : trimmedAPIKey,
                providerID: provider.rawValue
            )
            guard configuration.isConfigured else {
                showToast("请先填写接口地址、模型和 API Key")
                return
            }

            aiConnectionTesting = true
            defer { aiConnectionTesting = false }
            try await aiAPIConnectionTester.testConnection(configuration: configuration)
            showToast("API 连接成功")
        } catch {
            showToast("API 连接失败：\(error.localizedDescription)")
        }
    }

    func refreshSystemColorScheme() {
        let appearance = NSApp.effectiveAppearance
        let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
        let newColorScheme: ColorScheme = bestMatch == .darkAqua ? .dark : .light
        systemColorScheme = newColorScheme
        JarvisDockIconController.shared.apply(
            theme: themePreference,
            isSystemDark: newColorScheme == .dark
        )
    }

    func loadThemePreference() {
        guard let rawValue = UserDefaults.standard.string(forKey: themePreferenceKey),
              let preference = JarvisTheme(rawValue: rawValue)
        else {
            return
        }
        themePreference = preference
    }

    func loadLaunchAtLoginPreference() {
        launchAtLoginEnabled = JarvisLaunchAtLoginPreference.load(from: .standard)
    }

    func loadSelectedAIProvider() {
        let stored = UserDefaults.standard.string(forKey: selectedAIProviderKey)
            ?? UserDefaults.standard.string(forKey: "jarvis.web.conversation.provider")
        guard let rawValue = stored,
              let provider = AIConversationProvider(rawValue: rawValue)
        else {
            return
        }
        selectedAIProvider = provider
    }

    func selectAIProvider(_ provider: AIConversationProvider) {
        selectedAIProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: selectedAIProviderKey)
    }

    func loadSelectedEntertainmentPlatform() {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedEntertainmentPlatformKey),
              let platform = EntertainmentPlatform(rawValue: rawValue)
        else {
            return
        }
        selectedEntertainmentPlatform = platform
    }

    func selectEntertainmentPlatform(_ platform: EntertainmentPlatform) {
        let previous = selectedEntertainmentPlatform
        guard previous != platform else { return }

        entertainmentControllers[previous]?.suspendMediaPlayback()
        selectedEntertainmentPlatform = platform
        UserDefaults.standard.set(platform.rawValue, forKey: selectedEntertainmentPlatformKey)
        entertainmentControllers[platform]?.resumeMediaPlayback()
    }

    func suspendSelectedEntertainmentMedia() {
        entertainmentControllers[selectedEntertainmentPlatform]?.suspendMediaPlayback()
    }

    func resumeSelectedEntertainmentMedia() {
        entertainmentControllers[selectedEntertainmentPlatform]?.resumeMediaPlayback()
    }

    func synchronizeLaunchAtLogin() {
        guard launchAtLoginEnabled else { return }

        do {
            try launchAtLoginService.register()
        } catch {
            JarvisLog.error(
                category: .lifecycle,
                event: "launchAtLogin.register.failed",
                error: error
            )
        }
    }

    @discardableResult
    func updateScreenshotShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        let previous = screenshotShortcut
        guard let manager = screenshotShortcutManager else {
            statusMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        guard validation == .available else {
            screenshotShortcutConflictMessage = validation.message
            statusMessage = validation.message
            return false
        }
        guard manager.update(shortcut) else {
            _ = manager.update(previous)
            screenshotShortcut = previous
            screenshotShortcutConflictMessage = "快捷键注册失败，可能与其他应用或系统快捷键冲突"
            statusMessage = screenshotShortcutConflictMessage
            return false
        }

        screenshotShortcut = shortcut
        screenshotShortcutConflictMessage = ""
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: screenshotShortcutKey)
        }
        statusMessage = "截图快捷键已更新为 \(shortcut.displayString)"
        return true
    }

    @discardableResult
    func validateScreenshotShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        guard let manager = screenshotShortcutManager else {
            screenshotShortcutConflictMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        screenshotShortcutConflictMessage = validation == .available ? "" : validation.message
        return validation == .available
    }

    @discardableResult
    func updateClipboardShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        let previous = clipboardShortcut
        guard let manager = clipboardShortcutManager else {
            statusMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        guard validation == .available else {
            clipboardShortcutConflictMessage = validation.message
            statusMessage = validation.message
            return false
        }
        guard manager.update(shortcut) else {
            _ = manager.update(previous)
            clipboardShortcut = previous
            clipboardShortcutConflictMessage = "快捷键注册失败，可能与其他应用或系统快捷键冲突"
            statusMessage = clipboardShortcutConflictMessage
            return false
        }

        clipboardShortcut = shortcut
        clipboardShortcutConflictMessage = ""
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: clipboardShortcutKey)
        }
        statusMessage = "剪贴板快捷键已更新为 \(shortcut.displayString)"
        return true
    }

    @discardableResult
    func validateClipboardShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        guard let manager = clipboardShortcutManager else {
            clipboardShortcutConflictMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        clipboardShortcutConflictMessage = validation == .available ? "" : validation.message
        return validation == .available
    }

    @discardableResult
    func updateMeetingShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        let previous = meetingShortcut
        guard let manager = meetingShortcutManager else {
            statusMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        guard validation == .available else {
            meetingShortcutConflictMessage = validation.message
            statusMessage = validation.message
            return false
        }
        guard manager.update(shortcut) else {
            _ = manager.update(previous)
            meetingShortcut = previous
            meetingShortcutConflictMessage = "快捷键注册失败，可能与其他应用或系统快捷键冲突"
            statusMessage = meetingShortcutConflictMessage
            return false
        }

        meetingShortcut = shortcut
        meetingShortcutConflictMessage = ""
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: meetingShortcutKey)
        }
        statusMessage = "录音快捷键已更新为 \(shortcut.displayString)"
        return true
    }

    @discardableResult
    func validateMeetingShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        guard let manager = meetingShortcutManager else {
            meetingShortcutConflictMessage = "快捷键服务尚未就绪"
            return false
        }
        let validation = manager.validate(shortcut)
        meetingShortcutConflictMessage = validation == .available ? "" : validation.message
        return validation == .available
    }

    // MARK: - UserDefaults loading

    func loadScreenshotShortcut() {
        guard let data = UserDefaults.standard.data(forKey: screenshotShortcutKey),
              let shortcut = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data)
        else {
            UserDefaults.standard.set(true, forKey: screenshotShortcutDefaultMigrationKey)
            return
        }

        // The previous build could leave a custom or stale binding behind while
        // F1 is now the product default. Migrate that binding once; any custom
        // shortcut selected after this build is preserved on future launches.
        if !UserDefaults.standard.bool(forKey: screenshotShortcutDefaultMigrationKey)
            || shortcut == .legacyDefault
            || shortcut == .previousDefault
        {
            screenshotShortcut = .default
            if let migratedData = try? JSONEncoder().encode(ScreenshotShortcut.default) {
                UserDefaults.standard.set(migratedData, forKey: screenshotShortcutKey)
            }
            UserDefaults.standard.set(true, forKey: screenshotShortcutDefaultMigrationKey)
            return
        }

        screenshotShortcut = shortcut
    }

    func loadClipboardShortcut() {
        guard let data = UserDefaults.standard.data(forKey: clipboardShortcutKey),
              let shortcut = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data)
        else {
            return
        }
        clipboardShortcut = shortcut
    }

    func loadMeetingShortcut() {
        guard let data = UserDefaults.standard.data(forKey: meetingShortcutKey),
              let shortcut = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data)
        else {
            return
        }
        meetingShortcut = shortcut
    }
}
