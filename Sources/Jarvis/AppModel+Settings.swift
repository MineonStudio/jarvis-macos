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

    // MARK: - Screenshot translation settings

    func loadScreenshotTranslationSettings() {
        let configuration: ScreenshotTranslationConfiguration
        do {
            let apiKey = try AIAPIKeychain.shared.read()
            configuration = ScreenshotTranslationConfiguration.load(resolvedAPIKey: apiKey)
        } catch {
            screenshotTranslationAPIKeyConfigured = false
            screenshotTranslationAPIKeyMask = ""
            screenshotTranslationSettingsLocked = false
            screenshotTranslationEndpoint = ScreenshotTranslationConfiguration.defaultEndpoint
            screenshotTranslationModel = ScreenshotTranslationConfiguration.defaultModel
            showToast("读取 API Key 失败：\(error.localizedDescription)")
            return
        }
        screenshotTranslationEndpoint = configuration.endpoint
        screenshotTranslationModel = configuration.model
        let hasAPIKey = !configuration.apiKey.isEmpty
        screenshotTranslationAPIKeyConfigured = hasAPIKey
        screenshotTranslationAPIKeyMask = hasAPIKey ? "••••••••" : ""
        screenshotTranslationSettingsLocked = hasAPIKey
    }

    @discardableResult
    func saveScreenshotTranslationSettings(
        endpoint: String,
        model: String,
        apiKey: String
    ) -> Bool {
        do {
            let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEndpoint.isEmpty, !trimmedModel.isEmpty else {
                showToast("请填写接口地址和模型")
                return false
            }

            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedAPIKey = try AIAPIKeychain.shared.read() ?? ""
            let resolvedAPIKey = trimmedAPIKey.isEmpty ? storedAPIKey : trimmedAPIKey
            guard !resolvedAPIKey.isEmpty else {
                showToast("请输入 API Key")
                return false
            }

            if !trimmedAPIKey.isEmpty {
                try AIAPIKeychain.shared.write(trimmedAPIKey)
            }
            UserDefaults.standard.set(
                trimmedEndpoint,
                forKey: ScreenshotTranslationConfiguration.endpointKey
            )
            UserDefaults.standard.set(
                trimmedModel,
                forKey: ScreenshotTranslationConfiguration.modelKey
            )
            screenshotTranslationEndpoint = trimmedEndpoint
            screenshotTranslationModel = trimmedModel
            screenshotTranslationAPIKeyConfigured = true
            screenshotTranslationAPIKeyMask = "••••••••"
            screenshotTranslationSettingsLocked = true
            showToast("AI API 配置已保存")
            refreshDailyQuote(force: true)
            return true
        } catch {
            showToast("保存 AI API 配置失败：\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func clearScreenshotTranslationAPIKey() -> Bool {
        do {
            try AIAPIKeychain.shared.delete()
            screenshotTranslationAPIKeyConfigured = false
            screenshotTranslationAPIKeyMask = ""
            screenshotTranslationSettingsLocked = false
            showToast("已清除 AI API Key")
            refreshDailyQuote()
            return true
        } catch {
            showToast("清除 AI API Key 失败：\(error.localizedDescription)")
            return false
        }
    }

    func editScreenshotTranslationSettings() {
        screenshotTranslationSettingsLocked = false
    }

    func testScreenshotTranslationConnection(
        endpoint: String,
        model: String,
        apiKey: String
    ) async {
        guard !screenshotTranslationConnectionTesting else { return }

        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let storedAPIKey = try AIAPIKeychain.shared.read() ?? ""
            let configuration = AIAPIConfiguration(
                endpoint: trimmedEndpoint,
                model: trimmedModel,
                apiKey: trimmedAPIKey.isEmpty ? storedAPIKey : trimmedAPIKey
            )
            guard configuration.isConfigured else {
                showToast("请先填写接口地址、模型和 API Key")
                return
            }

            screenshotTranslationConnectionTesting = true
            defer { screenshotTranslationConnectionTesting = false }
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
        guard let rawValue = UserDefaults.standard.string(forKey: selectedAIProviderKey),
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

    func synchronizeLaunchAtLogin() {
        guard launchAtLoginEnabled else { return }

        do {
            try launchAtLoginService.register()
        } catch {
            NSLog("Jarvis could not register as a login item: \(error.localizedDescription)")
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
}
