import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: Hashable, Identifiable {
    case overview
    case skill(SkillID)
    case settings

    var id: String {
        switch self {
        case .overview: return "overview"
        case .skill(let skill): return "skill.\(skill.id)"
        case .settings: return "settings"
        }
    }

    var title: String {
        switch self {
        case .overview: return "总览"
        case .skill(let skill): return skill.title
        case .settings: return "设置"
        }
    }

    var navigationTitle: String {
        switch self {
        case .overview: return "总览"
        case .skill(.screenshot): return "截图"
        case .skill(.clipboard): return "剪贴板"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .skill(let skill): return skill.icon
        case .settings: return "gearshape"
        }
    }

    var skill: SkillID? {
        if case .skill(let skill) = self { return skill }
        return nil
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .overview
    @Published var modelConfiguration = ModelConfiguration()
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var latestScreenshotData: Data?
    @Published var screenshotHistory: [ScreenshotHistoryItem] = []
    @Published var latestTranslation = ""
    @Published var targetLanguage: ScreenshotTranslationLanguage = .chinese
    @Published private(set) var screenshotTranslationState: ScreenshotTranslationState = .idle
    @Published var isCapturing = false
    @Published var statusMessage = "系统就绪"
    @Published var connectionStatus = "尚未测试连接"
    @Published var screenshotShortcut = ScreenshotShortcut.default
    @Published var screenshotShortcutConflictMessage = ""
    @Published var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @Published var clipboardShortcutConflictMessage = ""
    @Published var themePreference: JarvisTheme = .system
    @Published private(set) var systemColorScheme: ColorScheme = .light
    @Published var updateState: JarvisUpdateState = .idle

    let modelGateway = ModelGateway()
    private let clipboardService = ClipboardService()
    private let clipboardStore = ClipboardStore()
    private let clipboardPanelController = ClipboardPanelController()
    private let screenshotCacheStore = ScreenshotCacheStore()
    private let screenshotHistoryStore = ScreenshotHistoryStore()
    private let overlayController = OverlayController()
    private let screenshotController = ScreenshotCaptureController()
    private let screenshotHistoryPreviewController = ScreenshotHistoryPreviewController()
    private let clipboardMediaPreviewController = ClipboardMediaPreviewController()
    private let updateService = JarvisUpdateService()
    private var screenshotShortcutManager: ScreenshotShortcutManager?
    private var clipboardShortcutManager: ScreenshotShortcutManager?
    private var systemAppearanceObservation: NSKeyValueObservation?
    private var editingHistoryID: UUID?

    private let configurationKey = "jarvis.model.configuration"
    private let screenshotShortcutKey = "jarvis.screenshot.shortcut"
    private let screenshotShortcutDefaultMigrationKey = "jarvis.screenshot.shortcut.f1.migrated"
    private let clipboardShortcutKey = "jarvis.clipboard.shortcut"
    private let themePreferenceKey = "jarvis.theme.preference"
    private let translationLanguageKey = "jarvis.screenshot.translation.language"
    private var translationTask: Task<Void, Never>?
    private var translationRequestID = UUID()
    private var translationSourceData: Data?
    private var translationSourceText: String?

    var screenshotTranslationProgress: ScreenshotTranslationProgress {
        screenshotController.translationProgress
    }

    init() {
        clipboardItems = clipboardStore.load()
        latestScreenshotData = screenshotCacheStore.load()
        screenshotHistory = screenshotHistoryStore.load()
        // Preserve the cache created by older builds as the first history item
        // when upgrading to the persistent history format.
        if screenshotHistory.isEmpty,
           let latestScreenshotData,
           let migratedItem = screenshotHistoryStore.add(data: latestScreenshotData) {
            screenshotHistory = [migratedItem]
        }
        loadConfiguration()
        loadScreenshotShortcut()
        loadClipboardShortcut()
        loadThemePreference()
        loadTranslationLanguage()
        refreshSystemColorScheme()
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshSystemColorScheme()
            }
        }

        if latestScreenshotData != nil {
            statusMessage = "已恢复上次缓存的截图"
        }

        screenshotShortcutManager = ScreenshotShortcutManager(binding: screenshotShortcut) { [weak self] in
            Task { @MainActor [weak self] in
                self?.captureScreenshot()
            }
        }

        clipboardShortcutManager = ScreenshotShortcutManager(
            binding: clipboardShortcut,
            hotKeyID: 2
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.showClipboardPanel()
            }
        }

        clipboardService.start { [weak self] item in
            Task { @MainActor [weak self] in
                self?.receiveClipboardItem(item)
            }
        }
    }

    var hasAPIKey: Bool {
        KeychainStore.shared.value(for: "jarvis.api-key") != nil
    }

    var apiKeyHint: String {
        hasAPIKey ? "API Key 已安全保存到 macOS 钥匙串" : "尚未配置 API Key"
    }

    func saveModelSettings(apiKey: String) {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainStore.shared.setValue(apiKey, for: "jarvis.api-key")
        }

        if let data = try? JSONEncoder().encode(modelConfiguration) {
            UserDefaults.standard.set(data, forKey: configurationKey)
        }
        statusMessage = "模型配置已保存"
    }

    func updateThemePreference(_ preference: JarvisTheme) {
        themePreference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: themePreferenceKey)
    }

    private func refreshSystemColorScheme() {
        let appearance = NSApp.effectiveAppearance
        let bestMatch = appearance.bestMatch(from: [.aqua, .darkAqua])
        systemColorScheme = bestMatch == .darkAqua ? .dark : .light
    }

    private func loadThemePreference() {
        guard let rawValue = UserDefaults.standard.string(forKey: themePreferenceKey),
              let preference = JarvisTheme(rawValue: rawValue) else {
            return
        }
        themePreference = preference
    }

    func clearAPIKey() {
        KeychainStore.shared.deleteValue(for: "jarvis.api-key")
        connectionStatus = "API Key 已删除"
        statusMessage = "API Key 已从钥匙串删除"
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

    func testConnection(apiKeyOverride: String = "") {
        let key = apiKeyOverride.isEmpty
            ? (KeychainStore.shared.value(for: "jarvis.api-key") ?? "")
            : apiKeyOverride

        guard !key.isEmpty else {
            connectionStatus = "请先填写 API Key"
            return
        }

        connectionStatus = "正在测试连接…"
        Task {
            do {
                try await modelGateway.testConnection(configuration: modelConfiguration, apiKey: key)
                connectionStatus = "连接成功 · \(modelConfiguration.modelName)"
            } catch {
                connectionStatus = "连接失败：\(error.localizedDescription)"
            }
        }
    }

    /// Starts a screenshot from a global/menu-bar action without changing the
    /// section currently shown in the main window. Callers that originate
    /// inside the main window can select the screenshot tab themselves before
    /// invoking this method.
    func captureScreenshot() {
        guard screenshotController.sessionPhase == .idle else {
            statusMessage = "请先完成当前截图操作"
            return
        }

        cancelScreenshotTranslation()

        editingHistoryID = nil
        guard screenshotController.requestScreenCaptureAccess() else {
            isCapturing = false
            // CGRequestScreenCaptureAccess() presents macOS's native Screen
            // Recording permission flow. Do not add a Jarvis-owned alert or
            // activate the host window on top of that system UI.
            statusMessage = "等待 macOS 屏幕录制权限"
            return
        }

        // Capture the desktop before activating Jarvis. The custom overlay is
        // shown only after ScreenCaptureKit has returned frozen pixels, so the
        // host window is never included in the screenshot.
        isCapturing = true
        statusMessage = "请在屏幕上框选区域"

        screenshotController.beginCapture { [weak self] result in
            guard let self else { return }
            isCapturing = false

            switch result {
            case .success(let session):
                statusMessage = "截图已保留在冻结画面上，可以直接编辑"
                screenshotController.showResult(
                    session,
                    translationProgress: screenshotTranslationProgress
                ) { [weak self] action in
                    self?.handleScreenshotAction(action)
                }
            case .failure(let error):
                statusMessage = error.localizedDescription
                switch error {
                case ScreenshotError.cancelled, ScreenshotError.permissionDenied:
                    // Keep normal cancellation and native permission failures
                    // from pulling the Jarvis host window in front of the user.
                    break
                default:
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private func handleScreenshotAction(_ action: ScreenshotAction) {
        switch action {
        case .saveRequested, .confirmRequested:
            // The capture controller consumes these requests and renders the
            // final image before sending the completed action back here.
            break
        case .save(let data):
            let presentingWindow = screenshotController.saveWindow()
            saveScreenshot(
                data,
                historyID: editingHistoryID,
                presentingWindow: presentingWindow
            )
        case .confirm(let data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            cancelScreenshotTranslation()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            statusMessage = "截图已确认并复制到剪贴板"
        case .pin(let data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            cancelScreenshotTranslation()
            statusMessage = "截图已贴在屏幕上"
        case .cancel:
            cancelScreenshotTranslation()
            editingHistoryID = nil
            statusMessage = "已取消截图编辑，未执行任何操作"
        case .translateRequested(let data):
            translateScreenshot(data: data)
        case .tool(let tool):
            statusMessage = "已选择\(tool.title)，在截图上拖动即可使用"
        case .undo:
            statusMessage = "已撤销上一步标注"
        case .redo:
            statusMessage = "已恢复上一步标注"
        case .delete:
            statusMessage = "已删除选中的标注"
        case .duplicate:
            statusMessage = "已复制选中的标注"
        }
    }

    private func saveScreenshot(
        _ data: Data,
        historyID: UUID?,
        presentingWindow: NSWindow? = nil
    ) {
        presentSavePanel(
            for: data,
            historyID: historyID,
            finalizesHistory: true,
            successMessage: "截图已保存",
            presentingWindow: presentingWindow
        )
    }

    func saveScreenshotHistory(
        _ item: ScreenshotHistoryItem,
        presentingWindow: NSWindow? = nil
    ) {
        guard let data = screenshotHistoryStore.data(for: item) else {
            statusMessage = "历史截图文件不存在"
            reloadScreenshotHistory()
            return
        }
        presentSavePanel(
            for: data,
            historyID: nil,
            finalizesHistory: false,
            successMessage: "截图已保存",
            presentingWindow: presentingWindow
        )
    }

    func copyScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard let data = screenshotHistoryStore.data(for: item) else {
            statusMessage = "历史截图文件不存在"
            reloadScreenshotHistory()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        statusMessage = "截图已复制到剪贴板"
    }

    private func presentSavePanel(
        for data: Data,
        historyID: UUID?,
        finalizesHistory: Bool,
        successMessage: String,
        presentingWindow: NSWindow? = nil
    ) {
        let savePanel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        savePanel.nameFieldStringValue = "贾维斯-\(formatter.string(from: Date())).png"
        savePanel.canCreateDirectories = true
        if let presentingWindow {
            // The history preview is a high-level panel. Present the native
            // save dialog as its sheet so it stays above the screenshot and
            // the dimming panel instead of falling behind them.
            savePanel.level = presentingWindow.level
            savePanel.beginSheetModal(for: presentingWindow) { [weak self] response in
                self?.finishSavePanel(
                    savePanel,
                    response: response,
                    data: data,
                    historyID: historyID,
                    finalizesHistory: finalizesHistory,
                    successMessage: successMessage
                )
            }
        } else {
            savePanel.begin { [weak self] response in
                self?.finishSavePanel(
                    savePanel,
                    response: response,
                    data: data,
                    historyID: historyID,
                    finalizesHistory: finalizesHistory,
                    successMessage: successMessage
                )
            }
        }
    }

    private func finishSavePanel(
        _ savePanel: NSSavePanel,
        response: NSApplication.ModalResponse,
        data: Data,
        historyID: UUID?,
        finalizesHistory: Bool,
        successMessage: String
    ) {
        guard response == .OK, let url = savePanel.url else {
            statusMessage = "已取消保存"
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            if finalizesHistory {
                finalizeScreenshot(data, historyID: historyID)
            }
            statusMessage = successMessage
        } catch {
            statusMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func clearScreenshotCache() {
        cancelScreenshotTranslation()
        screenshotCacheStore.clear()
        latestScreenshotData = nil
        latestTranslation = ""
        statusMessage = "截图缓存已清除"
    }

    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let release = try await updateService.checkForLatestRelease()
                updateState = updateService.isNewer(
                    release.version,
                    than: JarvisAppVersion.shortVersion
                ) ? .available(release) : .upToDate
            } catch {
                updateState = .failed(message: error.localizedDescription)
            }
        }
    }

    func downloadAndInstallUpdate() {
        guard case .available(let release) = updateState else { return }
        updateState = .downloading(version: release.version)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                updateState = .downloading(version: release.version)
                try await updateService.downloadAndInstall(release)
                updateState = .installing(version: release.version)
                // The detached installer waits for this process to exit before
                // replacing the bundle and opening the updated app.
                try await Task.sleep(for: .milliseconds(250))
                NSApp.terminate(nil)
            } catch {
                updateState = .failed(message: error.localizedDescription)
            }
        }
    }

    func openLatestRelease() {
        if case .available(let release) = updateState {
            NSWorkspace.shared.open(release.releaseURL)
        } else {
            NSWorkspace.shared.open(JarvisAppVersion.releasesURL)
        }
    }

    private func setLatestScreenshot(_ data: Data) {
        latestScreenshotData = data
        screenshotCacheStore.save(data)
    }

    private func finalizeScreenshot(_ data: Data, historyID: UUID?) {
        setLatestScreenshot(data)
        if let historyID,
           let item = screenshotHistory.first(where: { $0.id == historyID }) {
            _ = screenshotHistoryStore.update(item, data: data)
        } else {
            _ = screenshotHistoryStore.add(data: data)
        }
        screenshotHistory = screenshotHistoryStore.load()
        editingHistoryID = nil
    }

    func screenshotHistoryData(for item: ScreenshotHistoryItem) -> Data? {
        screenshotHistoryStore.data(for: item)
    }

    func showScreenshotHistoryPreview(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            statusMessage = "请先完成当前截图操作"
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            statusMessage = "历史截图文件不存在"
            reloadScreenshotHistory()
            return
        }
        screenshotHistoryPreviewController.show(item: item, data: data, app: self)
    }

    func editScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            statusMessage = "请先完成当前截图操作"
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            statusMessage = "历史截图文件不存在"
            reloadScreenshotHistory()
            return
        }

        editingHistoryID = item.id
        selectedSection = .skill(.screenshot)
        statusMessage = "正在编辑历史截图"
        screenshotController.showHistoryResult(
            data: data,
            translationProgress: screenshotTranslationProgress
        ) { [weak self] action in
            self?.handleScreenshotAction(action)
        }
    }

    func deleteScreenshotHistory(_ item: ScreenshotHistoryItem) {
        if editingHistoryID == item.id {
            screenshotController.dismissResult()
            editingHistoryID = nil
        }
        let deletedData = screenshotHistoryStore.data(for: item)
        screenshotHistoryStore.delete(item)
        reloadScreenshotHistory()

        if let deletedData, latestScreenshotData == deletedData {
            if let replacement = screenshotHistory.first,
               let replacementData = screenshotHistoryStore.data(for: replacement) {
                setLatestScreenshot(replacementData)
            } else {
                screenshotCacheStore.clear()
                latestScreenshotData = nil
                latestTranslation = ""
                screenshotTranslationState = .idle
            }
        }
        statusMessage = "已删除历史截图"
    }

    private func reloadScreenshotHistory() {
        screenshotHistory = screenshotHistoryStore.load()
    }

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
            statusMessage = "请先在设置中配置 API Key"
            return
        }

        translationTask?.cancel()
        let requestID = UUID()
        translationRequestID = requestID
        translationSourceData = data
        translationSourceText = nil
        latestTranslation = ""
        screenshotTranslationState = .translating
        screenshotTranslationProgress.isTranslating = true
        screenshotTranslationProgress.isReviewingOCR = false
        statusMessage = "正在本地识别截图文字…"

        showTranslationOverlayLoading()

        translationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let recognizedText = try await Task.detached(priority: .userInitiated) {
                    try ScreenshotTextRecognizer.recognizeText(in: data)
                }.value
                try Task.checkCancellation()
                guard translationRequestID == requestID else { return }

                translationTask = nil
                translationSourceText = recognizedText
                screenshotTranslationState = .reviewingOCR(recognizedText)
                screenshotTranslationProgress.isTranslating = false
                screenshotTranslationProgress.isReviewingOCR = true
                statusMessage = "请校对识别出的原文…"
                overlayController.showOCRReview(
                    text: recognizedText,
                    targetLanguage: targetLanguage.rawValue,
                    anchorWindow: screenshotController.saveWindow(),
                    anchorFrame: screenshotController.translationAnchorFrame(),
                    onCancel: { [weak self] in self?.cancelScreenshotTranslation() },
                    onTranslate: { [weak self] text in self?.translateRecognizedText(text) }
                )
            } catch is CancellationError {
                return
            } catch {
                guard translationRequestID == requestID else { return }
                let message = error.localizedDescription
                screenshotTranslationState = .failed(message)
                screenshotTranslationProgress.isTranslating = false
                screenshotTranslationProgress.isReviewingOCR = false
                statusMessage = "翻译失败：\(error.localizedDescription)"
                overlayController.showError(
                    message: message,
                    targetLanguage: targetLanguage.rawValue,
                    anchorWindow: screenshotController.saveWindow(),
                    anchorFrame: screenshotController.translationAnchorFrame(),
                    onRetry: { [weak self] in self?.translateCurrentScreenshot() }
                )
            }
        }
    }

    private func translateRecognizedText(_ sourceText: String) {
        let normalizedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            statusMessage = "请至少保留一段要翻译的文字"
            return
        }

        let key = KeychainStore.shared.value(for: "jarvis.api-key") ?? ""
        guard !key.isEmpty else {
            selectedSection = .settings
            statusMessage = "请先在设置中配置 API Key"
            return
        }

        translationTask?.cancel()
        let requestID = translationRequestID
        translationSourceText = normalizedText
        screenshotTranslationState = .translating
        screenshotTranslationProgress.isTranslating = true
        screenshotTranslationProgress.isReviewingOCR = false
        statusMessage = "正在翻译识别出的文字…"

        showTranslationOverlayLoading()

        translationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await modelGateway.translateText(
                    normalizedText,
                    targetLanguage: targetLanguage.rawValue,
                    configuration: modelConfiguration,
                    apiKey: key
                )
                try Task.checkCancellation()
                guard translationRequestID == requestID else { return }
                translationTask = nil
                latestTranslation = result
                screenshotTranslationState = .success(result)
                screenshotTranslationProgress.isTranslating = false
                screenshotTranslationProgress.isReviewingOCR = false
                statusMessage = "翻译完成"
                overlayController.show(
                    text: result,
                    targetLanguage: targetLanguage.rawValue,
                    anchorWindow: screenshotController.saveWindow(),
                    anchorFrame: screenshotController.translationAnchorFrame(),
                    onRetry: { [weak self] in self?.translateCurrentScreenshot() }
                )
            } catch is CancellationError {
                return
            } catch {
                guard translationRequestID == requestID else { return }
                translationTask = nil
                let message = error.localizedDescription
                screenshotTranslationState = .failed(message)
                screenshotTranslationProgress.isTranslating = false
                screenshotTranslationProgress.isReviewingOCR = false
                statusMessage = "翻译失败：\(error.localizedDescription)"
                overlayController.showError(
                    message: message,
                    targetLanguage: targetLanguage.rawValue,
                    anchorWindow: screenshotController.saveWindow(),
                    anchorFrame: screenshotController.translationAnchorFrame(),
                    onRetry: { [weak self] in self?.translateCurrentScreenshot() }
                )
            }
        }
    }

    func translateCurrentScreenshot() {
        if let sourceText = translationSourceText,
           !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translateRecognizedText(sourceText)
            return
        }

        let data = screenshotController.currentEditingPNGData() ?? translationSourceData ?? latestScreenshotData
        guard let data else {
            statusMessage = "请先截取一块屏幕区域"
            return
        }
        translateScreenshot(data: data)
    }

    func showTranslationOverlay() {
        guard case .success(let text) = screenshotTranslationState else {
            statusMessage = "请先完成一次翻译"
            return
        }
        overlayController.show(
            text: text,
            targetLanguage: targetLanguage.rawValue,
            anchorWindow: screenshotController.saveWindow(),
            anchorFrame: screenshotController.translationAnchorFrame(),
            onRetry: { [weak self] in self?.translateCurrentScreenshot() }
        )
    }

    func updateTranslationLanguage(_ language: ScreenshotTranslationLanguage) {
        targetLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: translationLanguageKey)
    }

    private func loadTranslationLanguage() {
        guard let rawValue = UserDefaults.standard.string(forKey: translationLanguageKey),
              let language = ScreenshotTranslationLanguage(rawValue: rawValue) else {
            return
        }
        targetLanguage = language
    }

    private func showTranslationOverlayLoading() {
        overlayController.showLoading(
            targetLanguage: targetLanguage.rawValue,
            anchorWindow: screenshotController.saveWindow(),
            anchorFrame: screenshotController.translationAnchorFrame(),
            onRetry: { [weak self] in self?.translateCurrentScreenshot() }
        )
    }

    private func cancelScreenshotTranslation() {
        translationRequestID = UUID()
        translationTask?.cancel()
        translationTask = nil
        translationSourceData = nil
        translationSourceText = nil
        latestTranslation = ""
        screenshotTranslationState = .idle
        screenshotTranslationProgress.isTranslating = false
        screenshotTranslationProgress.isReviewingOCR = false
        overlayController.dismiss()
    }

    func receiveClipboardItem(_ item: ClipboardItem) {
        let matchingItems = clipboardItems.filter { $0.fingerprint == item.fingerprint }
        let wasPinned = matchingItems.contains(where: { $0.isPinned })
        clipboardStore.removeStoredFiles(for: matchingItems)

        var item = item
        item.isPinned = wasPinned
        clipboardItems.removeAll { $0.fingerprint == item.fingerprint }
        clipboardItems.insert(item, at: 0)
        let removedItems = Array(clipboardItems.dropFirst(300))
        clipboardItems = Array(clipboardItems.prefix(300))
        clipboardStore.removeStoredFiles(for: removedItems)
        clipboardStore.save(clipboardItems)
    }

    func copyClipboard(_ item: ClipboardItem) {
        guard writeClipboardItem(item) else {
            statusMessage = "内容已不可用，可能已被移动或删除"
            return
        }
        clipboardService.markCurrentPasteboardAsHandled()
        statusMessage = "已复制 \(item.preview)"
    }

    func showClipboardMediaPreview(_ item: ClipboardItem) {
        guard item.kind == .image || item.kind == .video else {
            copyClipboard(item)
            return
        }
        guard item.hasLocalContent else {
            statusMessage = "媒体文件已不可用"
            return
        }
        clipboardMediaPreviewController.show(item: item, app: self)
    }

    func showClipboardPanel() {
        clipboardPanelController.show(app: self)
    }

    func closeClipboardPanel() {
        clipboardPanelController.close()
    }

    func toggleClipboardPin(_ item: ClipboardItem) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == item.id }) else { return }
        clipboardItems[index].isPinned.toggle()
        clipboardItems.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
        clipboardStore.save(clipboardItems)
        statusMessage = clipboardItems.first(where: { $0.id == item.id })?.isPinned == true
            ? "已收藏剪贴板内容"
            : "已取消收藏"
    }

    func revealClipboardItem(_ item: ClipboardItem) {
        let path = item.kind == .image ? item.imagePath : item.filePath
        guard let path, FileManager.default.fileExists(atPath: path) else {
            statusMessage = "本地文件已不可用"
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @discardableResult
    func writeClipboardItem(_ item: ClipboardItem) -> Bool {
        let pasteboard = NSPasteboard.general

        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        case .image:
            guard let path = item.imagePath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = NSImage(data: data) else { return false }
            pasteboard.clearContents()
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(data, forType: .png)
            if let tiffData = image.tiffRepresentation {
                pasteboardItem.setData(tiffData, forType: .tiff)
            }
            return pasteboard.writeObjects([pasteboardItem])
        case .file, .video:
            guard let path = item.filePath,
                  FileManager.default.fileExists(atPath: path) else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
        }
    }

    func deleteClipboardItem(_ item: ClipboardItem) {
        clipboardStore.removeStoredFiles(for: [item])
        clipboardItems.removeAll { $0.id == item.id }
        clipboardStore.save(clipboardItems)
    }

    func clearClipboardHistory() {
        clipboardStore.removeStoredFiles(for: clipboardItems)
        clipboardItems.removeAll()
        clipboardStore.save(clipboardItems)
        statusMessage = "剪贴板历史已清空"
    }

    private func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(ModelConfiguration.self, from: data) else {
            return
        }
        modelConfiguration = configuration
    }

    private func loadScreenshotShortcut() {
        guard let data = UserDefaults.standard.data(forKey: screenshotShortcutKey),
              let shortcut = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data) else {
            UserDefaults.standard.set(true, forKey: screenshotShortcutDefaultMigrationKey)
            return
        }

        // The previous build could leave a custom or stale binding behind while
        // F1 is now the product default. Migrate that binding once; any custom
        // shortcut selected after this build is preserved on future launches.
        if !UserDefaults.standard.bool(forKey: screenshotShortcutDefaultMigrationKey)
            || shortcut == .legacyDefault
            || shortcut == .previousDefault {
            screenshotShortcut = .default
            if let migratedData = try? JSONEncoder().encode(ScreenshotShortcut.default) {
                UserDefaults.standard.set(migratedData, forKey: screenshotShortcutKey)
            }
            UserDefaults.standard.set(true, forKey: screenshotShortcutDefaultMigrationKey)
            return
        }

        screenshotShortcut = shortcut
    }

    private func loadClipboardShortcut() {
        guard let data = UserDefaults.standard.data(forKey: clipboardShortcutKey),
              let shortcut = try? JSONDecoder().decode(ScreenshotShortcut.self, from: data) else {
            return
        }
        clipboardShortcut = shortcut
    }
}
