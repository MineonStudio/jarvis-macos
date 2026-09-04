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

        let provider: AIAPIConfiguration
        do {
            let apiKey = try AIAPIKeychain.shared.read()
            provider = AIAPIConfiguration.load(resolvedAPIKey: apiKey)
        } catch {
            aiAPIKeyConfigured = false
            aiAPIKeyMask = ""
            aiSettingsLocked = false
            providerEndpoint = AIAPIConfiguration.defaultEndpoint
            providerName = ""
            providerModel = AIAPIConfiguration.defaultModel
            showToast("读取 API Key 失败：\(error.localizedDescription)")
            return
        }
        applyProviderConfiguration(provider)
        refreshAvailableAIModels()
    }

    @discardableResult
    func saveProviderSettings(
        name: String,
        baseURL: String,
        model: String,
        apiKey: String,
        announce: Bool = true
    ) -> Bool {
        do {
            let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBaseURL.isEmpty else {
                showToast("请填写 base_url")
                return false
            }
            guard !AIAPIConfiguration.isKeylessEndpoint(trimmedBaseURL) else {
                showToast("请填写可用的接口地址")
                return false
            }
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedModel.isEmpty else {
                showToast("请填写模型")
                return false
            }

            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedAPIKey = try AIAPIKeychain.shared.read() ?? ""
            let resolvedAPIKey = trimmedAPIKey.isEmpty ? storedAPIKey : trimmedAPIKey
            guard !resolvedAPIKey.isEmpty else {
                showToast("请输入 API Key")
                return false
            }

            let endpoint = OpenAICompatibleAPIClient.normalizedEndpointURL(from: trimmedBaseURL)?
                .absoluteString ?? trimmedBaseURL
            var trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                trimmedName = AIModelOption.providerTitle(for: endpoint, isFree: false)
            }
            try persistProviderConfiguration(
                AIAPIConfiguration(
                    endpoint: endpoint,
                    model: trimmedModel,
                    apiKey: resolvedAPIKey,
                    name: trimmedName
                ),
                writeKeychain: !trimmedAPIKey.isEmpty
            )
            injectJarvisAPIIntoHermesIfNeeded()
            if announce {
                showToast("API 配置已保存")
            }
            refreshAvailableAIModels()
            return true
        } catch {
            showToast("保存 API 配置失败：\(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func clearAIAPIKey() -> Bool {
        do {
            try AIAPIKeychain.shared.delete()
            aiAPIKeyConfigured = false
            aiAPIKeyMask = ""
            aiSettingsLocked = false
            showToast("已清除 AI API Key")
            return true
        } catch {
            showToast("清除 AI API Key 失败：\(error.localizedDescription)")
            return false
        }
    }

    func editAIAPISettings() {
        aiSettingsLocked = false
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
        UserDefaults.standard.set(configuration.name, forKey: AIAPIConfiguration.apiNameKey)
        applyProviderConfiguration(configuration)
    }

    func selectAIModel(_ option: AIModelOption) {
        let trimmed = option.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hermesProvider = option.hermesProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = option.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = hermesProvider.isEmpty
            ? HermesProviderCatalog.slug(forEndpoint: endpoint)
            : hermesProvider
        guard !slug.isEmpty else { return }
        guard trimmed != hermesCurrentModel || slug != hermesCurrentProvider else { return }

        let baseURL = HermesProviderCatalog.descriptor(for: slug)?.baseURL
            ?? AIAPIConfiguration(endpoint: endpoint, model: trimmed, apiKey: "").openAIBaseURL
        do {
            try HermesAdapter.live().setCurrentModel(
                provider: slug,
                model: trimmed,
                baseURL: baseURL
            )
        } catch HermesError.profileMissing {
            showToast("请先创建 Jarvis Profile")
            return
        } catch {
            showToast("切换模型失败：\(error.localizedDescription)")
            return
        }

        let jarvisSlug = HermesProviderCatalog.slug(forEndpoint: providerEndpoint)
        if slug == jarvisSlug, !option.isFree {
            UserDefaults.standard.set(trimmed, forKey: AIAPIConfiguration.apiModelKey)
        }
        applyHermesCurrentModel(HermesAdapter.live().currentModel())
        showToast(option.isFree ? "已切换到 \(trimmed)（free）" : "已切换到 \(trimmed)")
    }

    func refreshAvailableAIModels() {
        aiModelsGeneration += 1
        let generation = aiModelsGeneration
        aiModelsLoading = true
        let currentModel = hermesCurrentModel
        let currentHermesProvider = hermesCurrentProvider
        let provider = AIAPIConfiguration.load()
        let cachedPaidModels = UserDefaults.standard.stringArray(forKey: AIAPIConfiguration.apiModelsKey)
            ?? UserDefaults.standard.stringArray(forKey: AIAPIConfiguration.paidModelsKey)
            ?? []

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if aiModelsGeneration == generation {
                    aiModelsLoading = false
                }
            }

            var paidModels = cachedPaidModels.filter {
                !HermesFreeModelCatalog.isAnonymousFreeModel($0)
            }
            if provider.isConfigured, !provider.isKeyless {
                if let livePaid = try? await OpenAICompatibleAPIClient().listModels(configuration: provider),
                   !livePaid.isEmpty
                {
                    paidModels = livePaid.filter { !HermesFreeModelCatalog.isAnonymousFreeModel($0) }
                    UserDefaults.standard.set(paidModels, forKey: AIAPIConfiguration.apiModelsKey)
                }
            }
            if !provider.model.isEmpty,
               !HermesFreeModelCatalog.isAnonymousFreeModel(provider.model),
               !paidModels.contains(provider.model)
            {
                paidModels.insert(provider.model, at: 0)
            }

            let hermesCache = HermesProviderCatalog.loadCachedModels()
            var options = AIModelOption.combine(
                paidModels: paidModels,
                paidEndpoint: provider.isKeyless ? "" : provider.endpoint,
                freeModels: [],
                cache: hermesCache,
                allowedSlugs: HermesProviderCatalog.explicitlyConfiguredSlugs(),
                paidTitle: provider.name
            )
            if !currentModel.isEmpty,
               !HermesFreeModelCatalog.isAnonymousFreeModel(currentModel),
               !options.contains(where: {
                   $0.model == currentModel && $0.hermesProvider == currentHermesProvider
               })
            {
                let descriptor = HermesProviderCatalog.descriptor(for: currentHermesProvider)
                options.insert(
                    AIModelOption(
                        model: currentModel,
                        isFree: false,
                        providerTitle: HermesProviderCatalog.groupTitle(
                            forSlug: currentHermesProvider,
                            endpoint: descriptor?.chatCompletionsURL ?? ""
                        ),
                        endpoint: descriptor?.chatCompletionsURL ?? "",
                        hermesProvider: currentHermesProvider
                    ),
                    at: 0
                )
            }
            guard aiModelsGeneration == generation else { return }
            availableAIModelOptions = options
        }
    }

    private func applyProviderConfiguration(_ configuration: AIAPIConfiguration) {
        providerEndpoint = configuration.endpoint
        providerName = configuration.name
        providerModel = configuration.model
        let hasAPIKey = !configuration.apiKey.isEmpty
        aiAPIKeyConfigured = hasAPIKey
        aiAPIKeyMask = hasAPIKey ? "••••••••" : ""
        aiSettingsLocked = hasAPIKey
    }

    func applyHermesCurrentModel(_ current: HermesCurrentModel?) {
        hermesCurrentProvider = current?.provider ?? ""
        hermesCurrentModel = current?.model ?? ""
    }

    func injectJarvisAPIIntoHermesIfNeeded() {
        let adapter = HermesAdapter.live()
        guard adapter.inspect().isProfileReady else { return }
        do {
            try adapter.injectAPIIfAbsent(AIAPIConfiguration.load())
            refreshHermesStatus()
        } catch {
            NSLog("Jarvis could not inject API into Hermes: \(error.localizedDescription)")
        }
    }

    func testAIAPIConnection(
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
                apiKey: trimmedAPIKey.isEmpty ? storedAPIKey : trimmedAPIKey
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
            ?? UserDefaults.standard.string(forKey: "jarvis.ai.conversation.provider")
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
