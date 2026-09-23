import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: Hashable, Identifiable {
    case home
    case aiConversation
    case entertainment
    case skill(SkillID)

    var id: String {
        switch self {
        case .home: "home"
        case .aiConversation: "ai-conversation"
        case .entertainment: "entertainment"
        case let .skill(skill): "skill.\(skill.id)"
        }
    }

    var title: String {
        switch self {
        case .home: "首页"
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        case let .skill(skill): skill.title
        }
    }

    var navigationTitle: String {
        switch self {
        case .home: "首页"
        case .aiConversation: "AI聚合"
        case .entertainment: "娱乐广场"
        case .skill(.screenshot): "截图"
        case .skill(.clipboard): "剪贴板"
        case .skill(.windowLayout): "窗口布局"
        case .skill(.resume): "简历制作"
        case .skill(.wallpaper): "桌面壁纸"
        case .skill(.meetingNotes): "会议记录"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .aiConversation: "sparkles"
        case .entertainment: "play.rectangle"
        case let .skill(skill): skill.icon
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
    /// 保存之后编辑会话是否结束。工具栏上的「保存」不结束（还能接着改），
    /// 所以它不能把 `editingHistoryID` 清掉。
    let endsSession: Bool
    let successMessage: String
}

@MainActor
@Observable
final class AppModel {
    var selectedSection: AppSection = .home
    var clipboardItems: [ClipboardItem] = []
    var latestScreenshotData: Data?
    var screenshotHistory: [ScreenshotHistoryItem] = []
    var isCapturing = false
    var statusMessage = "系统就绪"
    var toastMessage: String?
    var screenshotShortcut = ScreenshotShortcut.default
    var screenshotShortcutConflictMessage = ""
    var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    var clipboardShortcutConflictMessage = ""
    var meetingShortcut = ScreenshotShortcut.meetingDefault
    var meetingShortcutConflictMessage = ""
    var windowLayoutShortcuts: [WindowLayout: ScreenshotShortcut] = [:]
    var themePreference: JarvisTheme = .system
    var appIconAppearance: JarvisAppIconAppearance = .system
    var accentColorPreference: JarvisAccentColor = .system
    var systemColorScheme: ColorScheme = .light
    var activeColorScheme: ColorScheme {
        themePreference.resolvedColorScheme(system: systemColorScheme)
    }

    var updateState: JarvisUpdateState = .idle
    var selectedAIProvider: AIConversationProvider = .deepSeek
    var selectedEntertainmentPlatform: EntertainmentPlatform = .x
    var apiProvider: AIAPIProvider = .openAI
    var providerEndpoint = AIAPIConfiguration.defaultEndpoint
    var providerModel = AIAPIConfiguration.defaultModel
    var availableAIModels: [String] = []
    var aiModelsLoading = false
    var aiModelsRefreshError: String?
    var aiAPIKeyConfigured = false
    var aiAPIKeyMask = ""
    var aiSettingsLocked = false
    var aiConnectionTesting = false
    var meetingRecords: [MeetingRecord] = []
    var selectedMeetingID: UUID?
    var meetingProcessingState: MeetingProcessingState = .idle
    var meetingElapsed: TimeInterval = 0
    var meetingModelState: MeetingModelPreparationState = .checking
    var meetingModelAvailability = MeetingModelAvailability(
        speakerDiarizationReady: false,
        chineseTranscriptionReady: false
    )
    var canManageMeetingModels: Bool {
        guard meetingModelPreparationTask == nil,
              meetingCurrentRecordingID == nil,
              !isStartingMeetingRecording
        else {
            return false
        }
        switch meetingProcessingState {
        case .recording, .processing:
            return false
        default:
            return true
        }
    }

    var meetingStorageError: String?
    var screenCapturePermissionGranted = false
    var accessibilityPermissionGranted = false
    var microphonePermissionGranted = false
    var cameraPermissionGranted = false
    var launchAtLoginEnabled = JarvisLaunchAtLoginPreference.defaultValue
    var clipboardCacheDirectoryURL: URL
    var clipboardCacheMaximumBytes: Int64
    var clipboardCacheAutoCleanupEnabled = false
    var clipboardCacheAutoCleanupPeriod: ClipboardCacheCleanupPeriod = .never
    var automaticClipboardRecordingEnabled = true
    var hideSensitiveClipboardContent = true
    var taskPermissionPrompt: JarvisTaskPermissionPrompt?
    var clipboardCacheUsage = ClipboardCacheUsage(
        usedBytes: 0,
        capacityBytes: ClipboardCacheStore.defaultMaximumBytes,
        fileCount: 0
    )

    @ObservationIgnored let clipboardCacheStore: ClipboardCacheStore
    @ObservationIgnored let clipboardService: ClipboardService
    @ObservationIgnored lazy var clipboardStore = ClipboardStore()
    @ObservationIgnored lazy var clipboardHistoryWriter = ClipboardHistoryWriter(store: clipboardStore)
    @ObservationIgnored lazy var startupRepository = JarvisStartupRepository()
    @ObservationIgnored let clipboardPanelController = ClipboardPanelController()
    @ObservationIgnored lazy var screenshotCacheStore = ScreenshotCacheStore()
    @ObservationIgnored lazy var screenshotHistoryStore = ScreenshotHistoryStore()
    @ObservationIgnored let screenshotController = ScreenshotCaptureController()
    @ObservationIgnored let screenshotHistoryPreviewController = ScreenshotHistoryPreviewController()
    @ObservationIgnored let clipboardMediaPreviewController = ClipboardMediaPreviewController()
    @ObservationIgnored let updateService = JarvisUpdateService()
    @ObservationIgnored let aiConversationDownloadManager = AIConversationDownloadManager()
    @ObservationIgnored let meetingRepository: MeetingRepository
    @ObservationIgnored let meetingRecorder: MeetingRecorder
    @ObservationIgnored let meetingTranscriptionService: any MeetingTranscribing
    @ObservationIgnored let aiTextCompletionAPI: any AITextCompletionAPI
    @ObservationIgnored let entertainmentDownloadManager = AIConversationDownloadManager()
    @ObservationIgnored let entertainmentVideoDownloads = EntertainmentVideoDownloadManager()
    @ObservationIgnored let resumeWorkspace = ResumeWorkspace()
    @ObservationIgnored let launchAtLoginService = JarvisLaunchAtLoginService.shared
    @ObservationIgnored let aiAPIConnectionTester: any AIAPIConnectionTesting
    @ObservationIgnored private var aiConversationControllers: [AIConversationProvider: JarvisWebPlatformController] = [:]
    @ObservationIgnored private(set) var entertainmentControllers: [EntertainmentPlatform: JarvisWebPlatformController] = [:]
    @ObservationIgnored var startupTask: Task<Void, Never>?
    @ObservationIgnored var clipboardSaveTask: Task<Void, Never>?
    /// 剪贴板历史写入的版本号。每次落盘都取一个新值，连同当时的状态一起交给
    /// `ClipboardStore`，让迟到的去抖写入无法覆盖更新的直接写入。
    @ObservationIgnored var clipboardHistoryRevision: UInt64 = 0
    @ObservationIgnored var aiModelsRefreshTask: Task<Void, Never>?
    @ObservationIgnored var screenshotShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var clipboardShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var meetingShortcutManager: ScreenshotShortcutManager?
    @ObservationIgnored var windowLayoutShortcutManagers: [WindowLayout: ScreenshotShortcutManager] = [:]
    @ObservationIgnored var windowLayoutController: WindowLayoutController?
    @ObservationIgnored var systemAppearanceObservation: NSKeyValueObservation?
    @ObservationIgnored var editingHistoryID: UUID?
    @ObservationIgnored var clipboardCacheCleanupTimer: Timer?
    @ObservationIgnored var meetingRecordingTimer: Task<Void, Never>?
    @ObservationIgnored var meetingProcessingTask: Task<Void, Never>?
    @ObservationIgnored var meetingModelPreparationTask: Task<Void, Never>?
    @ObservationIgnored var meetingModelAvailabilityTask: Task<Void, Never>?
    @ObservationIgnored var meetingCurrentRecordingID: UUID?
    @ObservationIgnored var isStartingMeetingRecording = false
    @ObservationIgnored var meetingProcessingQueue: [MeetingProcessingJob] = []
    @ObservationIgnored var meetingActiveProcessingID: UUID?
    @ObservationIgnored var lastMeetingProgressStage: MeetingProcessingStage?
    @ObservationIgnored var lastMeetingProgressValue = -1.0

    @ObservationIgnored let screenshotShortcutKey = "jarvis.screenshot.shortcut"
    @ObservationIgnored let screenshotShortcutDefaultMigrationKey = "jarvis.screenshot.shortcut.f1.migrated"
    @ObservationIgnored let clipboardShortcutKey = "jarvis.clipboard.shortcut"
    @ObservationIgnored let meetingShortcutKey = "jarvis.meeting.shortcut"
    @ObservationIgnored let windowLayoutShortcutKeyPrefix = "jarvis.window-layout.shortcut."
    @ObservationIgnored let themePreferenceKey = "jarvis.theme.preference"
    @ObservationIgnored let appIconAppearanceKey = "jarvis.app-icon.appearance"
    @ObservationIgnored let accentColorPreferenceKey = "jarvis.accent-color.preference"
    @ObservationIgnored let clipboardCacheAutoCleanupEnabledKey = "jarvis.clipboard.cache.auto-cleanup.enabled"
    @ObservationIgnored let clipboardCacheAutoCleanupPeriodKey = "jarvis.clipboard.cache.auto-cleanup.period"
    @ObservationIgnored let clipboardRecordingEnabledKey = "jarvis.clipboard.recording.enabled"
    @ObservationIgnored let hideSensitiveClipboardContentKey = "jarvis.clipboard.hide-sensitive"
    @ObservationIgnored let selectedAIProviderKey = "jarvis.web.ai-provider"
    @ObservationIgnored let selectedEntertainmentPlatformKey = "jarvis.entertainment.platform"
    @ObservationIgnored var toastDismissTask: Task<Void, Never>?

    func aiConversationController(for provider: AIConversationProvider) -> JarvisWebPlatformController {
        if let controller = aiConversationControllers[provider] {
            return controller
        }

        let controller = JarvisWebPlatformController(
            platform: provider.webPlatform,
            downloadManager: aiConversationDownloadManager
        )
        aiConversationControllers[provider] = controller
        return controller
    }

    func entertainmentController(for platform: EntertainmentPlatform) -> JarvisWebPlatformController {
        if let controller = entertainmentControllers[platform] {
            return controller
        }

        let controller = JarvisWebPlatformController(
            platform: platform.webPlatform,
            downloadManager: entertainmentDownloadManager
        )
        entertainmentControllers[platform] = controller
        return controller
    }

    init(
        aiAPIConnectionTester: any AIAPIConnectionTesting = OpenAICompatibleAPIClient(),
        aiTextCompletionAPI: any AITextCompletionAPI = OpenAICompatibleAPIClient(),
        meetingTranscriptionService: any MeetingTranscribing = FluidAudioMeetingTranscriptionService()
    ) {
        self.aiAPIConnectionTester = aiAPIConnectionTester
        self.aiTextCompletionAPI = aiTextCompletionAPI
        self.meetingTranscriptionService = meetingTranscriptionService
        let cacheStore = ClipboardCacheStore()
        clipboardCacheStore = cacheStore
        clipboardService = ClipboardService(cacheStore: cacheStore)
        clipboardCacheDirectoryURL = cacheStore.currentDirectoryURL
        clipboardCacheMaximumBytes = cacheStore.currentMaximumBytes
        let repository = MeetingRepository()
        meetingRepository = repository
        let loadedMeetings = repository.load()
        meetingStorageError = loadedMeetings.errorMessage
        var loadedMeetingRecords = loadedMeetings.records
        for index in loadedMeetingRecords.indices {
            let original = loadedMeetingRecords[index]
            if MeetingRecord.isLegacyGeneratedTitle(original.title, createdAt: original.createdAt) {
                loadedMeetingRecords[index].title = MeetingRecord.defaultTitle
            }
            if loadedMeetingRecords[index].status == .summarizing,
               let detail = repository.loadDetail(for: loadedMeetingRecords[index].id)
            {
                loadedMeetingRecords[index].applyDetail(detail)
            }
            loadedMeetingRecords[index].applyInterruptedLaunchRecovery()
            if loadedMeetingRecords[index] != original {
                try? repository.save(loadedMeetingRecords[index])
            }
        }
        meetingRecords = loadedMeetingRecords
        meetingRecorder = MeetingRecorder()
        meetingRecorder.onUnexpectedStop = { [weak self] in
            self?.handleUnexpectedMeetingStop()
        }
        loadClipboardCacheCleanupSettings()
        loadScreenshotShortcut()
        loadClipboardShortcut()
        loadMeetingShortcut()
        loadWindowLayoutShortcuts()
        loadAIAPISettings()
        loadThemePreference()
        loadAppIconAppearance()
        loadAccentColorPreference()
        loadLaunchAtLoginPreference()
        refreshSystemColorScheme()
        systemAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshSystemColorScheme()
            }
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

        meetingShortcutManager = ScreenshotShortcutManager(
            binding: meetingShortcut,
            hotKeyID: 9
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleMeetingRecording()
            }
        }

        windowLayoutController = WindowLayoutController { [weak self] message in
            self?.showToast(message)
        }
        for (index, layout) in WindowLayout.allCases.enumerated() {
            windowLayoutShortcutManagers[layout] = ScreenshotShortcutManager(
                binding: windowLayoutShortcut(for: layout),
                hotKeyID: UInt32(index + 3)
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.applyWindowLayout(layout)
                }
            }
        }
        loadSelectedAIProvider()
        loadSelectedEntertainmentPlatform()
        refreshPermissionStatus()
        synchronizeLaunchAtLogin()
        refreshMeetingModelState()
        startDeferredStartup()
        JarvisLog.info(
            category: .lifecycle,
            event: "appModel.initialized",
            fields: [
                "clipboardCacheDirectory": JarvisLogRedactor.path(clipboardCacheDirectoryURL.path),
                "clipboardCacheCapacityBytes": String(clipboardCacheMaximumBytes)
            ]
        )
    }

    /// 显示器排布变化（拔插外接屏、改分辨率）时收拾场子。
    ///
    /// 贴图是常驻窗口：所在那块屏消失后它既点不到也拿不到焦点，Esc 也关不掉，
    /// 只能重启应用。完全出屏的直接销毁，还留在屏幕内的重新收进可见范围。
    func handleScreenParametersChange() {
        screenshotController.reconcilePinnedScreenshotsWithVisibleDisplays()
    }

    private func startDeferredStartup() {
        let startedAt = Date()
        JarvisLog.info(
            category: .lifecycle,
            event: "startup.load.begin"
        )
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            let snapshot = await startupRepository.load()
            guard !Task.isCancelled else { return }
            applyStartupSnapshot(snapshot)
            JarvisLog.info(
                category: .lifecycle,
                event: "startup.load.complete",
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
                result: "success",
                fields: [
                    "clipboardRecordCount": String(snapshot.clipboardItems.count),
                    "screenshotRecordCount": String(snapshot.screenshotHistory.count)
                ]
            )
        }
    }

    private func applyStartupSnapshot(_ snapshot: JarvisStartupSnapshot) {
        clipboardItems = snapshot.clipboardItems
        screenshotHistory = snapshot.screenshotHistory
        latestScreenshotData = snapshot.cachedScreenshot
        clipboardCacheUsage = snapshot.clipboardCacheUsage

        let audit = clipboardCacheStore.audit(items: clipboardItems)
        JarvisLog.notice(
            category: .clipboard,
            event: "cache.startupAudit",
            result: audit.missingReferenceCount == 0 ? "healthy" : "missingReferences",
            fields: audit.logFields(autoCleanupEnabled: clipboardCacheAutoCleanupEnabled).merging(
                [
                    "directory": JarvisLogRedactor.path(clipboardCacheDirectoryURL.path)
                ],
                uniquingKeysWith: { _, new in new }
            )
        )

        // Preserve the cache created by older builds as the first history item
        // when upgrading to the persistent history format.
        if screenshotHistory.isEmpty,
           let cachedScreenshot = snapshot.cachedScreenshot,
           let migratedItem = screenshotHistoryStore.add(data: cachedScreenshot)
        {
            screenshotHistory = [migratedItem]
        }

        trimClipboardCacheIfNeeded()
        migrateClipboardTextCache()
        configureClipboardRecording()
        configureClipboardCacheAutoCleanup()
        if latestScreenshotData != nil {
            statusMessage = "已恢复上次缓存的截图"
        }
        JarvisPerformance.emit("startup services ready")
        JarvisLog.info(
            category: .lifecycle,
            event: "startup.servicesReady",
            fields: [
                "clipboardService": "running",
                "clipboardRecordCount": String(clipboardItems.count),
                "screenshotRecordCount": String(screenshotHistory.count)
            ]
        )
    }

    deinit {
        toastDismissTask?.cancel()
        startupTask?.cancel()
        clipboardSaveTask?.cancel()
        aiModelsRefreshTask?.cancel()
        meetingRecordingTimer?.cancel()
        meetingProcessingTask?.cancel()
        meetingModelPreparationTask?.cancel()
        meetingModelAvailabilityTask?.cancel()
    }
}

extension AppModel {
    // MARK: - Screenshot workflow

    /// Starts a screenshot from a global/menu-bar action without changing the
    /// section currently shown in the main window. Callers that originate
    /// inside the main window can select the screenshot tab themselves before
    /// invoking this method.
    func captureScreenshot() {
        refreshPermissionStatus()
        guard screenCapturePermissionGranted else {
            promptForTaskPermission(.screenCapture)
            return
        }
        guard screenshotController.sessionPhase == .idle else {
            showToast(JarvisFeedbackCopy.finishScreenshotFirst)
            return
        }

        editingHistoryID = nil
        // Freeze every display on this run-loop turn, then show the overlay
        // on those pixels. The overlay is created after the snapshot, so it
        // is never included in the screenshot.
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
                case ScreenshotError.invalidSelection:
                    showToast(JarvisFeedbackCopy.recapture)
                case ScreenshotError.noDisplays:
                    showToast(JarvisFeedbackCopy.noDisplays)
                default:
                    showToast(JarvisFeedbackCopy.captureFailed)
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
            showToast(JarvisFeedbackCopy.copied)
        case let .pin(data):
            finalizeScreenshot(data, historyID: editingHistoryID)
            showToast(JarvisFeedbackCopy.saved)
        case .copiedToClipboard:
            showToast(JarvisFeedbackCopy.copied)
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
            endsSession: false,
            successMessage: JarvisFeedbackCopy.saved,
            presentingWindow: presentingWindow
        )
    }

    func copyScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast(JarvisFeedbackCopy.fileMissing)
            reloadScreenshotHistory()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        showToast(JarvisFeedbackCopy.copied)
    }

    private func presentSavePanel(
        for data: Data,
        historyID: UUID?,
        finalizesHistory: Bool,
        endsSession: Bool,
        successMessage: String,
        presentingWindow: NSWindow? = nil
    ) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = ScreenshotFileName.timestamped()
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
                        endsSession: endsSession,
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
                        endsSession: endsSession,
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
            // 真存下盘了才叫「存过」。保存面板点取消会直接 return 到这里之前，
            // 贴图那场编辑不该因为弹过一次面板就认定自己存过东西。
            screenshotController.notePinnedEditSaved(request.data)
            if request.finalizesHistory {
                finalizeScreenshot(
                    request.data,
                    historyID: request.historyID,
                    endsSession: request.endsSession
                )
            }
            showToast(request.successMessage)
        } catch {
            showToast(JarvisFeedbackCopy.saveFailed)
        }
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
                    showToast(JarvisFeedbackCopy.latestVersion)
                }
            } catch {
                updateState = .failed(message: error.localizedDescription)
                showToast(JarvisFeedbackCopy.updateCheckFailed)
            }
        }
    }

    func downloadAndInstallUpdate() {
        guard case let .available(release) = updateState else { return }
        // Ad-hoc updates replace the code identity, so TCC must be reset
        // before install. Warn first; the actual tccutil reset runs inside
        // `JarvisUpdateService.downloadAndInstall`. Installations that carry
        // the local signing identity keep theirs.
        if !JarvisLocalSigning.isAvailable {
            let alert = NSAlert()
            alert.messageText = "安装后需要重新授权"
            alert.informativeText = "这次更新会清除屏幕录制和辅助功能授权。"
            alert.addButton(withTitle: "继续")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
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
                showToast(JarvisFeedbackCopy.updateFailed)
            }
        }
    }

    @discardableResult
    private func setLatestScreenshot(_ data: Data) -> Bool {
        latestScreenshotData = data
        guard screenshotCacheStore.save(data) else {
            showToast(JarvisFeedbackCopy.cacheSaveFailed)
            return false
        }
        return true
    }

    /// 落盘之后 `editingHistoryID` 该变成什么。
    ///
    /// - 会话结束（「完成」「贴图」）→ 清空。
    /// - 会话继续（「保存」）→ 记住这次落在哪条（新截图第一次保存时本来是空的），
    ///   否则下一次保存/完成会再新增一条一模一样的记录。
    nonisolated static func editingHistoryIDAfterFinalize(
        endsSession: Bool,
        resolvedID: UUID?,
        current: UUID?
    ) -> UUID? {
        endsSession ? nil : (resolvedID ?? current)
    }

    /// - Parameter endsSession: 这次落盘之后编辑会话是否就结束了。点「完成」「贴图」
    ///   会结束；点「保存」不会——用户可以接着编辑。会话没结束时要把这次落在历史里
    ///   的条目 id 记回 `editingHistoryID`，否则下一次保存/完成会再新增一条一模一样
    ///   的记录（新截图第一保存时 id 本来是空的，正好踩中）。
    private func finalizeScreenshot(_ data: Data, historyID: UUID?, endsSession: Bool = true) {
        let historyItem = historyID.flatMap { id in
            screenshotHistory.first(where: { $0.id == id })
        }
        let cacheStore = screenshotCacheStore
        let historyStore = screenshotHistoryStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cacheSaved = cacheStore.save(data)
            // 这次落盘实际对应的条目 id：更新时是原来那条，新建时是刚加进去那条。
            let resolvedID: UUID? = if let historyItem {
                historyStore.update(historyItem, data: data) != nil ? historyItem.id : nil
            } else {
                historyStore.add(data: data)?.id
            }
            let history = historyStore.load()
            DispatchQueue.main.async {
                guard let self else { return }
                self.latestScreenshotData = cacheSaved ? data : self.latestScreenshotData
                self.screenshotHistory = history
                self.editingHistoryID = Self.editingHistoryIDAfterFinalize(
                    endsSession: endsSession,
                    resolvedID: resolvedID,
                    current: self.editingHistoryID
                )
                if !cacheSaved || resolvedID == nil {
                    self.showToast(JarvisFeedbackCopy.historySaveFailed)
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

    func showScreenshotHistoryPreview(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            showToast(JarvisFeedbackCopy.finishScreenshotFirst)
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast(JarvisFeedbackCopy.fileMissing)
            reloadScreenshotHistory()
            return
        }
        guard screenshotHistoryPreviewController.show(data: data) else {
            showToast(JarvisFeedbackCopy.cannotPreview)
            return
        }
    }

    func editScreenshotHistory(_ item: ScreenshotHistoryItem) {
        guard screenshotController.sessionPhase == .idle else {
            showToast(JarvisFeedbackCopy.finishScreenshotFirst)
            return
        }
        guard let data = screenshotHistoryStore.data(for: item) else {
            showToast(JarvisFeedbackCopy.fileMissing)
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
            // 走「取消」那条路，而不是直接把编辑面拆掉：会话以为自己是被人关掉的，
            // 跟着它走的东西（比如贴图）就收不到交代。
            screenshotController.cancelActiveSession()
            editingHistoryID = nil
        }
        let deletedData = screenshotHistoryStore.data(for: item)
        guard screenshotHistoryStore.delete(item) else {
            showToast(JarvisFeedbackCopy.deleteFailed)
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
                    showToast(JarvisFeedbackCopy.cacheClearFailed)
                    return
                }
                latestScreenshotData = nil
            }
        }
        showToast(JarvisFeedbackCopy.deleted)
    }

    private func reloadScreenshotHistory() {
        screenshotHistory = screenshotHistoryStore.load()
    }
}
