import AppKit
import SwiftUI

enum SettingsLayout {
    static let contentMaxWidth: CGFloat = 760
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarMinimumWidth: CGFloat = 180
    static let sidebarMaximumWidth: CGFloat = 240
    static let modalSize = CGSize(width: 1_040, height: 680)
}

enum SettingsSection: String, CaseIterable, Hashable, Identifiable {
    case general
    case appearance
    case shortcuts
    case model
    case diagnostics
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "常规"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .model: "模型"
        case .diagnostics: "诊断"
        case .about: "关于"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .model: "cube"
        case .diagnostics: "waveform.path.ecg"
        case .about: "info.circle"
        }
    }
}

struct SettingsCardHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 24, height: 24)
            Text(title)
                .font(JarvisTypography.bodyEmphasis)
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
            VStack(alignment: .leading, spacing: 15) {
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

                Divider().overlay(Color.primary.opacity(0.12))

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

                Divider().overlay(Color.primary.opacity(0.12))

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
                .font(JarvisTypography.bodyEmphasis)
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
            VStack(alignment: .leading, spacing: 15) {
                SettingsCardHeader(
                    title: "窗口布局快捷键",
                    systemImage: "macwindow.on.rectangle"
                )

                ForEach(Array(WindowLayout.allCases.enumerated()), id: \.element) { index, layout in
                    if index > 0 {
                        Divider().overlay(Color.primary.opacity(0.12))
                    }
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
                .font(JarvisTypography.bodyEmphasis)
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
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(selection.title)
                            .font(.system(size: 22, weight: .semibold))
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
            ClipboardCacheSettingsCard()
            ScreenshotLanguagePackSettingsCard()
            permissionSettingsCard
        case .appearance:
            themeSettingsCard
        case .shortcuts:
            ShortcutSettingsCard()
            WindowLayoutShortcutSettingsCard()
        case .model:
            AIAPISettingsCard()
            MeetingModelSettingsCard()
        case .diagnostics:
            DiagnosticsSettingsCard()
        case .about:
            versionAndUpdateCard
            sourceRepositoryCard
        }
    }

    private var versionAndUpdateCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                SettingsCardHeader(
                    title: "版本与更新",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                Spacer(minLength: 8)
                updateControls
            }
        }
    }

    @ViewBuilder
    private var updateControls: some View {
        switch app.updateState {
        case let .available(release):
            HStack(spacing: 10) {
                Text(displayVersion(release.version))
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                Button("下载新版本") {
                    app.downloadAndInstallUpdate()
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .accessibilityLabel("下载新版本 \(displayVersion(release.version))")
            }
        case .checking:
            HStack(spacing: 8) {
                versionLabel
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在检查更新")
            }
        case let .downloading(version):
            HStack(spacing: 8) {
                Text(displayVersion(version))
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在下载更新")
            }
        case let .installing(version):
            HStack(spacing: 8) {
                Text(displayVersion(version))
                    .font(JarvisTypography.monospaced)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在安装更新")
            }
        default:
            HStack(spacing: 10) {
                versionLabel
                Button {
                    app.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.jarvisTextSecondary)
                .contentShape(Circle())
                .accessibilityLabel("检查更新")
            }
        }
    }

    private var versionLabel: some View {
        Text("v\(JarvisAppVersion.shortVersion)")
            .font(JarvisTypography.monospaced)
            .foregroundStyle(Color.jarvisTextSecondary)
            .lineLimit(1)
    }

    private func displayVersion(_ version: String) -> String {
        version.lowercased().hasPrefix("v") ? version : "v\(version)"
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
            HStack(spacing: 14) {
                SettingsCardHeader(
                    title: "开源仓库",
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
                Spacer(minLength: 8)
                Button {
                    guard let url = URL(string: "https://github.com/MineonStudio/jarvis-macos") else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("访问 GitHub", systemImage: "arrow.up.right")
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }
        }
    }

    private var permissionSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsCardHeader(title: "权限", systemImage: "lock.shield")
                HStack {
                    Text(permissionSummary)
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(permissionSummaryColor)
                    Spacer(minLength: 8)
                }
                JarvisPermissionList(cornerRadius: 12)
            }
        }
    }

    private var permissionSummary: String {
        let grantedCount = JarvisRequiredPermission.allCases.count {
            app.isRequiredPermissionGranted($0)
        }
        return "已获取 \(grantedCount)/\(JarvisRequiredPermission.allCases.count)"
    }

    private var permissionSummaryColor: Color {
        app.hasAllRequiredPermissions ? .green : .orange
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SettingsCardHeader(title: "诊断日志", systemImage: "waveform.path.ecg")
                Spacer(minLength: 8)
                Button("导出日志") {
                    app.exportDiagnostics()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("导出最近的脱敏运行日志和剪贴板缓存统计")
                    .font(.system(size: 12, weight: .medium))
                Text("不包含剪贴板正文、凭据或完整外部文件路径")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SettingsCardHeader(title: "会议识别模型", systemImage: "waveform.and.person.filled")
                Spacer(minLength: 8)
                modelStatusLabel
                modelAction
            }

            if case let .downloading(stage, progress) = app.meetingModelState {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(stage.title)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(JarvisTypography.monospaced)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    .font(JarvisTypography.caption)
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                }
            }

            if case let .failed(message) = app.meetingModelState {
                Text(message)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var modelStatusLabel: some View {
        Group {
            switch app.meetingModelState {
            case .checking:
                Label("检查中", systemImage: "arrow.triangle.2.circlepath")
            case .notReady:
                Label("待下载", systemImage: "arrow.down.circle")
                    .foregroundStyle(Color.jarvisTextSecondary)
            case .downloading:
                Label("下载中", systemImage: "arrow.down.circle")
                    .foregroundStyle(Color.accentColor)
            case .ready:
                Label("已就绪", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Label("未就绪", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .font(JarvisTypography.bodyEmphasis)
    }

    @ViewBuilder
    private var modelAction: some View {
        switch app.meetingModelState {
        case .checking, .ready:
            EmptyView()
        case .downloading:
            Button("取消") {
                app.cancelMeetingModelPreparation()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        case .notReady, .failed:
            Button("下载模型") {
                app.prepareMeetingModels()
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
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
