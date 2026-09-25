import AppKit
import SwiftUI

enum SettingsLayout {
    static let contentMaxWidth: CGFloat = 760
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarMinimumWidth: CGFloat = 180
    static let sidebarMaximumWidth: CGFloat = 240
    static let modalSize = CGSize(width: 1040, height: 680)
}

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case appearance
    case wallpaperSources
    case shortcuts
    case model
    case privacyCache
    case diagnostics
    case about

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general: "常规"
        case .privacyCache: "隐私与缓存"
        case .appearance: "外观"
        case .wallpaperSources: "壁纸源"
        case .shortcuts: "快捷键"
        case .model: "模型"
        case .diagnostics: "诊断"
        case .about: "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .privacyCache: "lock.shield"
        case .appearance: "paintbrush"
        case .wallpaperSources: "photo.stack"
        case .shortcuts: "keyboard"
        case .model: "cube"
        case .diagnostics: "waveform.path.ecg"
        case .about: "info.circle"
        }
    }
}

enum SettingsTypography {
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let itemTitle = Font.system(size: 13, weight: .semibold)
    static let itemSubtitle = Font.system(size: 12)
}

enum SettingsFormMetrics {
    static let cardContentSpacing: CGFloat = 14
    static let sectionSpacing: CGFloat = 16
    static let labelSpacing: CGFloat = 8
    static let controlHeight: CGFloat = 34
    static let disabledControlOpacity = 0.82
}

struct SettingsCardHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 22, height: 22)
            Text(title)
                .font(SettingsTypography.cardTitle)
        }
    }
}

struct ShortcutSettingsCard: View {
    @Environment(AppModel.self) private var app
    @State private var screenshotShortcut = ScreenshotShortcut.default
    @State private var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @State private var meetingShortcut = ScreenshotShortcut.meetingDefault
    @State private var isRecordingScreenshotShortcut = false
    @State private var isRecordingClipboardShortcut = false
    @State private var isRecordingMeetingShortcut = false

    var body: some View {
        JarvisCard {
            content
        }
        .onAppear {
            screenshotShortcut = app.screenshotShortcut
            clipboardShortcut = app.clipboardShortcut
            meetingShortcut = app.meetingShortcut
            _ = app.validateScreenshotShortcut(screenshotShortcut)
            _ = app.validateClipboardShortcut(clipboardShortcut)
            _ = app.validateMeetingShortcut(meetingShortcut)
        }
        .onChange(of: screenshotShortcut) { _, newValue in
            guard isRecordingScreenshotShortcut else { return }
            if app.validateScreenshotShortcut(newValue) {
                guard newValue != app.screenshotShortcut else { return }
                _ = app.updateScreenshotShortcut(newValue)
            }
        }
        .onChange(of: clipboardShortcut) { _, newValue in
            guard isRecordingClipboardShortcut else { return }
            if app.validateClipboardShortcut(newValue) {
                guard newValue != app.clipboardShortcut else { return }
                _ = app.updateClipboardShortcut(newValue)
            }
        }
        .onChange(of: meetingShortcut) { _, newValue in
            guard isRecordingMeetingShortcut else { return }
            if app.validateMeetingShortcut(newValue) {
                guard newValue != app.meetingShortcut else { return }
                _ = app.updateMeetingShortcut(newValue)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            SettingsCardHeader(title: "快捷键", systemImage: "keyboard")

            shortcutRow(
                title: "截图",
                shortcut: $screenshotShortcut,
                isRecording: $isRecordingScreenshotShortcut,
                conflictMessage: app.screenshotShortcutConflictMessage
            ) {
                let previous = screenshotShortcut
                if !app.updateScreenshotShortcut(.default) {
                    screenshotShortcut = previous
                } else {
                    screenshotShortcut = .default
                }
            }

            shortcutRow(
                title: "剪贴板",
                shortcut: $clipboardShortcut,
                isRecording: $isRecordingClipboardShortcut,
                conflictMessage: app.clipboardShortcutConflictMessage
            ) {
                let previous = clipboardShortcut
                if !app.updateClipboardShortcut(.clipboardDefault) {
                    clipboardShortcut = previous
                } else {
                    clipboardShortcut = .clipboardDefault
                }
            }

            shortcutRow(
                title: "录音",
                shortcut: $meetingShortcut,
                isRecording: $isRecordingMeetingShortcut,
                conflictMessage: app.meetingShortcutConflictMessage
            ) {
                let previous = meetingShortcut
                if !app.updateMeetingShortcut(.meetingDefault) {
                    meetingShortcut = previous
                } else {
                    meetingShortcut = .meetingDefault
                }
            }
        }
    }

    private func shortcutRow(
        title: String,
        shortcut: Binding<ScreenshotShortcut>,
        isRecording: Binding<Bool>,
        conflictMessage: String,
        onRestore: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .font(SettingsTypography.itemTitle)
            Spacer(minLength: 8)
            ShortcutRecorderControl(
                shortcut: shortcut,
                isRecording: isRecording
            )
            .frame(width: 170, height: 32)
            if !conflictMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Button("恢复默认", action: onRestore)
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }
}

struct WindowLayoutShortcutSettingsCard: View {
    var body: some View {
        JarvisCard {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            SettingsCardHeader(
                title: "窗口布局快捷键",
                systemImage: "macwindow.on.rectangle"
            )

            ForEach(WindowLayout.allCases, id: \.self) { layout in
                WindowLayoutShortcutRow(layout: layout)
            }
        }
    }
}

private struct WindowLayoutShortcutRow: View {
    @Environment(AppModel.self) private var app

    let layout: WindowLayout

    @State private var shortcut = ScreenshotShortcut.default
    @State private var isRecording = false
    @State private var conflictMessage = ""

    var body: some View {
        HStack(spacing: 14) {
            Text(layout.title)
                .font(SettingsTypography.itemTitle)
            Spacer(minLength: 8)
            ShortcutRecorderControl(
                shortcut: $shortcut,
                isRecording: $isRecording
            )
            .frame(width: 170, height: 32)
            if !conflictMessage.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help(conflictMessage)
            }
            Button("恢复默认", action: restoreDefault)
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
        .onAppear {
            shortcut = app.windowLayoutShortcut(for: layout)
            conflictMessage = validationMessage(for: shortcut)
        }
        .onChange(of: shortcut) { _, newValue in
            guard isRecording else { return }
            let validation = app.validateWindowLayoutShortcut(layout, newValue)
            conflictMessage = validation == .available ? "" : validation.message
            guard validation == .available else { return }
            guard newValue != app.windowLayoutShortcut(for: layout) else { return }
            guard app.updateWindowLayoutShortcut(layout, newValue) else {
                shortcut = app.windowLayoutShortcut(for: layout)
                conflictMessage = validationMessage(for: shortcut)
                return
            }
        }
    }

    private func restoreDefault() {
        let defaultShortcut = layout.defaultShortcut
        guard app.updateWindowLayoutShortcut(layout, defaultShortcut) else {
            shortcut = app.windowLayoutShortcut(for: layout)
            conflictMessage = validationMessage(for: shortcut)
            return
        }
        shortcut = defaultShortcut
        conflictMessage = ""
    }

    private func validationMessage(for shortcut: ScreenshotShortcut) -> String {
        let validation = app.validateWindowLayoutShortcut(layout, shortcut)
        return validation == .available ? "" : validation.message
    }
}

struct SettingsView: View {
    let onClose: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: SettingsSection = .general
    @AppStorage(WallpaperSourcePreferences.storageKey)
    private var enabledWallpaperSources = WallpaperSourcePreferences.defaultStorageValue

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView {
                JarvisSidebarNavigation(
                    topItems: SettingsSection.allCases,
                    selection: $selection,
                    title: { $0.title },
                    icon: { $0.icon },
                    headerTitle: "设置",
                    showsHeaderOrb: false
                )
                .navigationSplitViewColumnWidth(
                    min: SettingsLayout.sidebarMinimumWidth,
                    ideal: SettingsLayout.sidebarIdealWidth,
                    max: SettingsLayout.sidebarMaximumWidth
                )
                .toolbar(removing: .sidebarToggle)
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(selection.title)
                            .font(SettingsTypography.pageTitle)
                            .foregroundStyle(.primary)

                        detailContent
                    }
                    .frame(maxWidth: SettingsLayout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JarvisMetrics.pageInset)
                }
                .background(Color.jarvisBackground)
            }
            .navigationSplitViewStyle(.balanced)
            .background(Color.jarvisBackground)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisTextSecondary)
                .accessibilityLabel("关闭设置")
                .padding(.top, 15)
                .padding(.trailing, 15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .general:
            launchAtLoginSettingsCard
            ScreenshotLanguagePackSettingsCard()
            permissionSettingsCard
        case .appearance:
            themeSettingsCard
            appIconSettingsCard
            accentColorSettingsCard
        case .wallpaperSources:
            WallpaperSourcesSettingsCard(enabledSourcesStorageValue: $enabledWallpaperSources)
        case .shortcuts:
            ShortcutSettingsCard()
            WindowLayoutShortcutSettingsCard()
        case .model:
            AIAPISettingsCard()
            MeetingModelSettingsCard()
        case .privacyCache:
            ClipboardPrivacySettingsCard()
            ClipboardCacheSettingsCard()
        case .diagnostics:
            DiagnosticsSettingsCard()
        case .about:
            versionAndUpdateCard
            sourceRepositoryCard
        }
    }

    private var versionAndUpdateCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                SettingsCardHeader(
                    title: "版本与更新",
                    systemImage: "arrow.triangle.2.circlepath"
                )

                HStack(alignment: .center, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("当前版本")
                            .font(SettingsTypography.itemSubtitle)
                            .foregroundStyle(Color.jarvisTextSecondary)
                        Text("Jarvis \(JarvisAppVersion.shortVersion)")
                            .font(SettingsTypography.itemSubtitle)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    Spacer(minLength: 8)
                    updateControls
                }

                HStack {
                    Spacer(minLength: 0)
                    Text("来源：\(installSourceTitle)")
                        .font(SettingsTypography.itemSubtitle)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var updateControls: some View {
        switch app.updateState {
        case .checking:
            Button("检查中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case let .downloading(version):
            HStack(spacing: 8) {
                Text(displayVersion(version))
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                Button("下载中…") {}
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(true)
            }
        case let .readyToInstall(version):
            HStack(spacing: 8) {
                Text(displayVersion(version))
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisAccent)
                    .lineLimit(1)
                Button("退出并更新") {
                    app.installPreparedUpdateNow()
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
            }
        case let .installing(version):
            HStack(spacing: 8) {
                Text(displayVersion(version))
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                Button("安装中…") {}
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(true)
            }
        case let .failed(message):
            Button("重试") {
                app.checkForUpdates()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .help("更新操作失败：\(message)")
        default:
            Button("检查更新") {
                app.checkForUpdates()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }

    private func displayVersion(_ version: String) -> String {
        version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }

    private var installSourceTitle: String {
        switch JarvisInstallSource.current() {
        case "direct-download": "直接下载"
        case "dmg": "DMG"
        case "development": "开发版"
        default: "旧版或未知"
        }
    }

    private var themeSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                SettingsCardHeader(title: "主题", systemImage: "circle.lefthalf.filled")
                Spacer(minLength: 8)
                JarvisThemePicker(selection: Binding(
                    get: { app.themePreference },
                    set: { app.updateThemePreference($0) }
                ))
            }
        }
    }

    private var appIconSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                SettingsCardHeader(title: "应用图标", systemImage: "square.grid.2x2.fill")
                JarvisAppIconPicker(selection: Binding(
                    get: { app.appIconAppearance },
                    set: { app.updateAppIconAppearance($0) }
                ))
            }
        }
    }

    private var accentColorSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                SettingsCardHeader(title: "强调色", systemImage: "paintpalette")
                JarvisAccentColorPicker(selection: Binding(
                    get: { app.accentColorPreference },
                    set: { app.updateAccentColorPreference($0) }
                ))
            }
        }
    }

    private var launchAtLoginSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                SettingsCardHeader(title: "开机自启", systemImage: "power")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { app.launchAtLoginEnabled },
                    set: { app.updateLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .animation(
                    JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
                    value: app.launchAtLoginEnabled
                )
            }
        }
    }

    private var sourceRepositoryCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                SettingsCardHeader(
                    title: "开源仓库",
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
                HStack(spacing: 14) {
                    Text("github.com/MineonStudio/jarvis-macos")
                        .font(JarvisTypography.monospacedSmall)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 8)
                    Button {
                        guard let url = URL(string: "https://github.com/MineonStudio/jarvis-macos") else {
                            return
                        }
                        NSWorkspace.shared.open(url)
                    } label: {
                        Text("前往GitHub")
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                }
            }
        }
    }

    private var permissionSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "权限", systemImage: "lock.shield")
                JarvisPermissionList(cornerRadius: 12, mode: .settings)
            }
        }
    }
}

struct SettingsModalOverlay: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.34))
                .ignoresSafeArea()
                .contentShape(Rectangle())

            SettingsView {
                isPresented = false
            }
            .frame(
                width: SettingsLayout.modalSize.width,
                height: SettingsLayout.modalSize.height
            )
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
            }
            .shadow(color: Color.black.opacity(0.30), radius: 34, y: 18)
            .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand {
            isPresented = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置")
    }
}

struct DiagnosticsSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
            HStack(spacing: 14) {
                SettingsCardHeader(title: "诊断日志", systemImage: "waveform.path.ecg")
                Spacer(minLength: 8)
                Button("导出日志") {
                    app.exportDiagnostics()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
    }
}

struct MeetingModelSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            content
        }
        .onAppear {
            app.refreshMeetingModelState()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: SettingsFormMetrics.sectionSpacing) {
            SettingsCardHeader(title: "会议识别模型", systemImage: "waveform.and.person.filled")

            ForEach(MeetingModelPreparationStage.allCases) { stage in
                MeetingModelSettingsRow(stage: stage)
            }

            if case let .failed(nil, _, message) = app.meetingModelState {
                Text(message)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct MeetingModelSettingsRow: View {
    @Environment(AppModel.self) private var app
    let stage: MeetingModelPreparationStage

    private var isReady: Bool {
        app.meetingModelAvailability.isReady(for: stage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: SettingsFormMetrics.labelSpacing) {
                    Text(stage.title)
                        .font(SettingsTypography.itemTitle)
                    Text(stage.modelName)
                        .font(JarvisTypography.monospacedSmall)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)
                action
            }

            if case let .downloading(activeStage, progress) = app.meetingModelState,
               activeStage == stage
            {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(Color.jarvisAccent)
                    Text("下载中 · \(Int(progress * 100))%")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }

            if case let .failed(failedStage, operation, message) = app.meetingModelState,
               failedStage == stage
            {
                Text("\(operation == .remove ? "移除失败" : "下载失败")：\(message)")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var action: some View {
        switch app.meetingModelState {
        case .checking:
            Button("检查中") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case let .downloading(activeStage, _):
            if activeStage == stage {
                Button("取消") { app.cancelMeetingModelPreparation() }
                    .buttonStyle(JarvisSecondaryButtonStyle())
            } else {
                availabilityAction
            }
        case let .removing(activeStage):
            if activeStage == stage {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("移除中")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            } else {
                availabilityAction
            }
        case let .failed(failedStage, operation, _) where failedStage == stage:
            if operation == .remove {
                Button("重试移除", role: .destructive) {
                    app.removeMeetingModel(stage)
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
                .disabled(!app.canManageMeetingModels)
            } else {
                Button("重试下载") {
                    app.prepareMeetingModel(stage)
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .disabled(!app.canManageMeetingModels)
            }
        default:
            availabilityAction
        }
    }

    @ViewBuilder
    private var availabilityAction: some View {
        if isReady {
            Button("移除", role: .destructive) {
                app.removeMeetingModel(stage)
            }
            .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
            .disabled(!app.canManageMeetingModels)
            .help("移除本机下载的 \(stage.title) 模型")
        } else {
            Button("下载") {
                app.prepareMeetingModel(stage)
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
            .disabled(!app.canManageMeetingModels)
        }
    }
}

struct JarvisThemePicker: View {
    @Binding var selection: JarvisTheme

    var body: some View {
        JarvisSegmentedControl(items: Array(JarvisTheme.allCases), selection: $selection) { theme, isSelected in
            Text(theme.title)
                .font(JarvisTypography.controlEmphasis)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(
                    minWidth: 54,
                    minHeight: JarvisMetrics.segmentedItemHeight,
                    maxHeight: JarvisMetrics.segmentedItemHeight
                )
                .padding(.horizontal, 8)
                .padding(.vertical, JarvisMetrics.segmentedItemVerticalPadding)
                .contentShape(Capsule())
        }
    }
}

struct JarvisAppIconPicker: View {
    @Binding var selection: JarvisAppIconAppearance
    @Environment(AppModel.self) private var app

    var body: some View {
        let isSystemDark = app.activeColorScheme == .dark

        HStack(spacing: 10) {
            ForEach(JarvisAppIconAppearance.allCases) { appearance in
                let resolvedPreview = appearance.resolvedVariant(isSystemDark: isSystemDark)

                Button {
                    selection = appearance
                } label: {
                    VStack(spacing: 8) {
                        JarvisAppIconPreview(
                            appearance: appearance,
                            isSystemDark: isSystemDark
                        )
                        .id(resolvedPreview)
                        Text(appearance.title)
                            .font(JarvisTypography.controlEmphasis)
                            .foregroundStyle(selection == appearance ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selection == appearance
                            ? Color.jarvisAccent.opacity(0.12)
                            : Color.primary.opacity(0.045),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                selection == appearance
                                    ? Color.jarvisAccent.opacity(0.65)
                                    : Color.primary.opacity(0.08),
                                lineWidth: selection == appearance ? 1.2 : 0.75
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("应用图标：\(appearance.title)")
                .accessibilityAddTraits(selection == appearance ? .isSelected : [])
            }
        }
    }
}

private struct JarvisAppIconPreview: View {
    let appearance: JarvisAppIconAppearance
    let isSystemDark: Bool

    var body: some View {
        Group {
            if let image = JarvisDockIconController.shared.previewImage(
                for: appearance,
                isSystemDark: isSystemDark
            ) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: appearance.icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.jarvisAccent)
            }
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }
}

struct JarvisAccentColorPicker: View {
    @Binding var selection: JarvisAccentColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(JarvisAccentColor.allCases) { accent in
                Button {
                    selection = accent
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(accent.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.7)
                            }
                        Text(accent.title)
                            .font(JarvisTypography.micro)
                            .foregroundStyle(selection == accent ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        selection == accent
                            ? Color.jarvisAccent.opacity(0.12)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("强调色：\(accent.title)")
                .accessibilityAddTraits(selection == accent ? .isSelected : [])
            }
        }
    }
}

struct JarvisToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(JarvisTypography.captionEmphasis)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(0.15), radius: 14, y: 6)
            .frame(maxWidth: 520)
    }
}
