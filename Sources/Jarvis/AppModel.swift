import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: Hashable, Identifiable {
    case overview
    case aiConversation
    case skill(SkillID)
    case settings

    var id: String {
        switch self {
        case .overview: "overview"
        case .aiConversation: "ai-conversation"
        case let .skill(skill): "skill.\(skill.id)"
        case .settings: "settings"
        }
    }

    var title: String {
        switch self {
        case .overview: "总览"
        case .aiConversation: "聊天"
        case let .skill(skill): skill.title
        case .settings: "设置"
        }
    }

    var navigationTitle: String {
        switch self {
        case .overview: "总览"
        case .aiConversation: "聊天"
        case .skill(.screenshot): "截图"
        case .skill(.clipboard): "剪贴板"
        case .skill(.windowLayout): "窗口布局"
        case .skill(.resume): "简历制作"
        case .skill(.wallpaper): "桌面壁纸"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .aiConversation: "bubble.left.and.bubble.right"
        case let .skill(skill): skill.icon
        case .settings: "gearshape"
        }
    }

    var skill: SkillID? {
        if case let .skill(skill) = self {
            return skill
        }
        return nil
    }
}

private struct ScreenshotSaveRequest {
    let data: Data
    let historyID: UUID?
    let finalizesHistory: Bool
    let successMessage: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedSection: AppSection = .overview
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var latestScreenshotData: Data?
    @Published var screenshotHistory: [ScreenshotHistoryItem] = []
    @Published var isCapturing = false
    @Published var statusMessage = "系统就绪"
    @Published var toastMessage: String?
    @Published var screenshotShortcut = ScreenshotShortcut.default
    @Published var screenshotShortcutConflictMessage = ""
    @Published var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @Published var clipboardShortcutConflictMessage = ""
    @Published var themePreference: JarvisTheme = .system
    @Published var systemColorScheme: ColorScheme = .light
    @Published var updateState: JarvisUpdateState = .idle
    @Published var selectedAIProvider: AIConversationProvider = .deepSeek
    @Published var screenshotTranslationEndpoint = ScreenshotTranslationConfiguration.defaultEndpoint
    @Published var screenshotTranslationModel = ScreenshotTranslationConfiguration.defaultModel
    @Published var screenshotTranslationAPIKeyConfigured = false
    @Published var screenshotTranslationAPIKeyMask = ""
    @Published var screenshotTranslationSettingsLocked = false
    @Published var screenshotTranslationConnectionTesting = false
    @Published var screenCapturePermissionGranted = false
    @Published var accessibilityPermissionGranted = false
    @Published var launchAtLoginEnabled = JarvisLaunchAtLoginPreference.defaultValue
    @Published var clipboardCacheDirectoryURL: URL
    @Published var clipboardCacheMaximumBytes: Int64
    @Published var clipboardCacheAutoCleanupEnabled = false
    @Published var clipboardCacheAutoCleanupPeriod: ClipboardCacheCleanupPeriod = .sevenDays
    @Published var clipboardCacheUsage = ClipboardCacheUsage(
        usedBytes: 0,
        capacityBytes: ClipboardCacheStore.defaultMaximumBytes,
        fileCount: 0
    )

    let clipboardCacheStore: ClipboardCacheStore
    let clipboardService: ClipboardService
    let clipboardStore = ClipboardStore()
    let clipboardPanelController = ClipboardPanelController()
    let screenshotCacheStore = ScreenshotCacheStore()
    let screenshotHistoryStore = ScreenshotHistoryStore()
    let screenshotController = ScreenshotCaptureController()
    let screenshotHistoryPreviewController = ScreenshotHistoryPreviewController()
    let clipboardMediaPreviewController = ClipboardMediaPreviewController()
    let updateService = JarvisUpdateService()
    let aiConversationDownloadManager = AIConversationDownloadManager()
    let resumeWorkspace = ResumeWorkspace()
    let launchAtLoginService = JarvisLaunchAtLoginService.shared
    let aiAPIConnectionTester: any AIAPIConnectionTesting
    private var aiConversationControllers: [AIConversationProvider: AIConversationWebController] = [:]
    var screenshotShortcutManager: ScreenshotShortcutManager?
    var clipboardShortcutManager: ScreenshotShortcutManager?
    var windowLayoutShortcutManagers: [WindowLayout: ScreenshotShortcutManager] = [:]
    var windowLayoutController: WindowLayoutController?
    var systemAppearanceObservation: NSKeyValueObservation?
    var editingHistoryID: UUID?
    var clipboardCacheCleanupTimer: Timer?

    let screenshotShortcutKey = "jarvis.screenshot.shortcut"
    let screenshotShortcutDefaultMigrationKey = "jarvis.screenshot.shortcut.f1.migrated"
    let clipboardShortcutKey = "jarvis.clipboard.shortcut"
    let themePreferenceKey = "jarvis.theme.preference"
    let clipboardCacheAutoCleanupEnabledKey = "jarvis.clipboard.cache.auto-cleanup.enabled"
    let clipboardCacheAutoCleanupPeriodKey = "jarvis.clipboard.cache.auto-cleanup.period"
    var toastDismissTask: Task<Void, Never>?

    func aiConversationController(for provider: AIConversationProvider) -> AIConversationWebController {
        if let controller = aiConversationControllers[provider] {
            return controller
        }

        let controller = AIConversationWebController(
            provider: provider,
            downloadManager: aiConversationDownloadManager
        )
        aiConversationControllers[provider] = controller
        return controller
    }

    init(aiAPIConnectionTester: any AIAPIConnectionTesting = OpenAICompatibleAPIClient()) {
        self.aiAPIConnectionTester = aiAPIConnectionTester
        let cacheStore = ClipboardCacheStore()
        clipboardCacheStore = cacheStore
        clipboardService = ClipboardService(cacheStore: cacheStore)
        clipboardCacheDirectoryURL = cacheStore.currentDirectoryURL
        clipboardCacheMaximumBytes = cacheStore.currentMaximumBytes
        clipboardItems = clipboardStore.load()
        clipboardCacheUsage = cacheStore.usage()
        migrateClipboardTextCache()
        clipboardCacheUsage = cacheStore.usage()
        screenshotHistory = screenshotHistoryStore.load()
        // Preserve the cache created by older builds as the first history item
        // when upgrading to the persistent history format.
        if screenshotHistory.isEmpty,
           let cachedScreenshot = screenshotCacheStore.load(),
           let migratedItem = screenshotHistoryStore.add(data: cachedScreenshot)
        {
            latestScreenshotData = cachedScreenshot
            screenshotHistory = [migratedItem]
        }
        trimClipboardCacheIfNeeded()
        loadClipboardCacheCleanupSettings()
        loadScreenshotShortcut()
        loadClipboardShortcut()
        loadScreenshotTranslationSettings()
        loadThemePreference()
        loadLaunchAtLoginPreference()
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

        windowLayoutController = WindowLayoutController { [weak self] message in
            self?.showToast(message)
        }
        for (index, layout) in WindowLayout.allCases.enumerated() {
            windowLayoutShortcutManagers[layout] = ScreenshotShortcutManager(
                binding: layout.shortcut,
                hotKeyID: UInt32(index + 3)
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.applyWindowLayout(layout)
                }
            }
        }
        refreshPermissionStatus()
        synchronizeLaunchAtLogin()

        clipboardService.start(
            onChange: { [weak self] item in
                Task { @MainActor [weak self] in
                    self?.receiveClipboardItem(item)
                }
            },
            prepareCacheSpace: { [weak self] additionalBytes in
                DispatchQueue.main.sync {
                    self?.trimClipboardCacheIfNeeded(forAdditionalBytes: additionalBytes)
                }
            }
        )
        configureClipboardCacheAutoCleanup()
    }

    func loadLatestScreenshotIfNeeded() -> Data? {
        if let latestScreenshotData {
            return latestScreenshotData
        }
        guard let data = screenshotCacheStore.load() else { return nil }
        latestScreenshotData = data
        statusMessage = "已恢复上次缓存的截图"
        return data
    }

    deinit {
        toastDismissTask?.cancel()
        clipboardCacheCleanupTimer?.invalidate()
    }
}

extension AppModel {
    // MARK: - Screenshot workflow

    /// Starts a screenshot from a global/menu-bar action without changing the
    /// section currently shown in the main window. Callers that originate
    /// inside the main window can select the screenshot tab themselves before
    /// invoking this method.
    func captureScreenshot() {
        guard screenshotController.sessionPhase == .idle else {
            showToast("请先完成当前截图操作")
            return
        }

        editingHistoryID = nil
        guard requestScreenCapturePermission() else {
            isCapturing = false
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
            case let .success(session):
                statusMessage = "截图已保留在冻结画面上，可以直接编辑"
                screenshotController.showResult(
                    session
                ) { [weak self] action in
                    self?.handleScreenshotAction(action)
                }
            case let .failure(error):
                statusMessage = error.localizedDescription
                switch error {
                case ScreenshotError.cancelled, ScreenshotError.permissionDenied:
                    // Keep normal cancellation and native permission failures
                    // from pulling the Jarvis host window in front of the user.
                    break
                default:
                    showToast(error.localizedDescription)
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
        case let .save(data):
            let presentingWindow = screenshotController.saveWindow()
            saveScreenshot(
                data,
                historyID: editingHistoryID,
                presentingWindow: presentingWindow
            )
        case let .confirm(data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(data, forType: .png)
            showToast("截图已确认并复制到剪贴板")
        case let .pin(data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            showToast("截图已贴在屏幕上")
        case .cancel:
            editingHistoryID = nil
            statusMessage = "已取消截图编辑，未执行任何操作"
        default:
            handleEditorStatusAction(action)
        }
    }

    private func handleEditorStatusAction(_ action: ScreenshotAction) {
        switch action {
        case let .tool(tool):
            statusMessage = "已选择\(tool.title)，在截图上拖动即可使用"
        case .undo:
            statusMessage = "已撤销上一步标注"
        case .redo:
            statusMessage = "已恢复上一步标注"
        case .delete:
            statusMessage = "已删除选中的标注"
        case .duplicate:
            statusMessage = "已复制选中的标注"
        default:
            break
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
            showToast("历史截图文件不存在")
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
            showToast("历史截图文件不存在")
            reloadScreenshotHistory()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        showToast("截图已复制到剪贴板")
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
                    request: ScreenshotSaveRequest(
                        data: data,
                        historyID: historyID,
                        finalizesHistory: finalizesHistory,
                        successMessage: successMessage
                    )
                )
            }
        } else {
            savePanel.begin { [weak self] response in
                self?.finishSavePanel(
                    savePanel,
                    response: response,
                    request: ScreenshotSaveRequest(
                        data: data,
                        historyID: historyID,
                        finalizesHistory: finalizesHistory,
                        successMessage: successMessage
                    )
                )
            }
        }
    }

    private func finishSavePanel(
        _ savePanel: NSSavePanel,
        response: NSApplication.ModalResponse,
        request: ScreenshotSaveRequest
    ) {
        guard response == .OK, let url = savePanel.url else {
            return
        }
        do {
            try request.data.write(to: url, options: .atomic)
            if request.finalizesHistory {
                finalizeScreenshot(request.data, historyID: request.historyID)
            }
            showToast(request.successMessage)
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    func clearScreenshotCache() {
        guard screenshotCacheStore.clear() else {
            showToast("截图缓存清除失败")
            return
        }
        latestScreenshotData = nil
        showToast("截图缓存已清除")
    }

    func checkForUpdates() {
        guard updateState != .checking else { return }
        updateState = .checking
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let release = try await updateService.checkForLatestRelease()
                let hasNewVersion = updateService.isNewer(
                    release.version,
                    than: JarvisAppVersion.shortVersion
                )
                updateState = hasNewVersion ? .available(release) : .upToDate
                if !hasNewVersion {
                    showToast("当前已是最新版本")
                }
            } catch {
                updateState = .failed(message: error.localizedDescription)
            }
        }
    }

    func downloadAndInstallUpdate() {
        guard case let .available(release) = updateState else { return }
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
        if case let .available(release) = updateState {
            NSWorkspace.shared.open(release.releaseURL)
        } else {
            NSWorkspace.shared.open(JarvisAppVersion.releasesURL)
        }
    }

    @discardableResult
    private func setLatestScreenshot(_ data: Data) -> Bool {
        latestScreenshotData = data
        guard screenshotCacheStore.save(data) else {
            showToast("截图缓存保存失败")
            return false
        }
        return true
    }

    private func finalizeScreenshot(_ data: Data, historyID: UUID?) {
        let historyItem = historyID.flatMap { id in
            screenshotHistory.first(where: { $0.id == id })
        }
        let cacheStore = screenshotCacheStore
        let historyStore = screenshotHistoryStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cacheSaved = cacheStore.save(data)
            let historySaved: Bool = if let historyItem {
                historyStore.update(historyItem, data: data) != nil
            } else {
                historyStore.add(data: data) != nil
            }
            let history = historyStore.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.latestScreenshotData = cacheSaved ? data : self.latestScreenshotData
                self.screenshotHistory = history
                self.editingHistoryID = nil
                if !cacheSaved || !historySaved {
                    self.showToast("截图已完成，但历史记录保存失败")
                }
            }
        }
    }

    func screenshotHistoryData(for item: ScreenshotHistoryItem) -> Data? {
        screenshotHistoryStore.data(for: item)
    }

    func screenshotHistoryFileURL(for item: ScreenshotHistoryItem) -> URL {
        screenshotHistoryStore.fileURL(for: item)
    }

    func screenshotHistoryFileSize(for item: ScreenshotHistoryItem) -> Int64? {
        screenshotHistoryStore.fileSize(for: item)
    }

    func showScreenshotHistoryPreview(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            showToast("请先完成当前截图操作")
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast("历史截图文件不存在")
            reloadScreenshotHistory()
            return
        }
        screenshotHistoryPreviewController.show(data: data)
    }

    func editScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            showToast("请先完成当前截图操作")
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast("历史截图文件不存在")
            reloadScreenshotHistory()
            return
        }

        editingHistoryID = item.id
        selectedSection = .skill(.screenshot)
        statusMessage = "正在编辑历史截图"
        screenshotController.showHistoryResult(
            data: data
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
        guard screenshotHistoryStore.delete(item) else {
            showToast("历史截图删除失败")
            reloadScreenshotHistory()
            return
        }
        reloadScreenshotHistory()

        if let deletedData, latestScreenshotData == deletedData {
            if let replacement = screenshotHistory.first,
               let replacementData = screenshotHistoryStore.data(for: replacement)
            {
                guard setLatestScreenshot(replacementData) else { return }
            } else {
                guard screenshotCacheStore.clear() else {
                    showToast("截图缓存清除失败")
                    return
                }
                latestScreenshotData = nil
            }
        }
        showToast("已删除历史截图")
    }

    private func reloadScreenshotHistory() {
        screenshotHistory = screenshotHistoryStore.load()
    }
}
