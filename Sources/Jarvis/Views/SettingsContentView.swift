import AppKit
import SwiftUI

private enum SettingsLayout {
    static let contentMaxWidth: CGFloat = 760
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
                    .help(conflictMessage)
            }
            Button("恢复默认", action: onRestore)
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(placement: .navigation) {
                    EmptyView()
                }
            },
            trailingToolbar: {
                ToolbarItem(placement: .automatic) {
                    EmptyView()
                }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        versionAndUpdateCard

                        themeSettingsCard

                        launchAtLoginSettingsCard
                        AIAPISettingsCard()
                        ClipboardCacheSettingsCard()
                        DiagnosticsSettingsCard()

                        ScreenshotLanguagePackSettingsCard()

                        MeetingModelSettingsCard()

                        ShortcutSettingsCard()
                    }
                    .frame(maxWidth: SettingsLayout.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JarvisMetrics.pageInset)
                }
            }
        )
        .onAppear {
            app.refreshPermissionStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissionStatus()
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
                .help("检查更新")
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
}

struct DiagnosticsSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
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
}

struct MeetingModelSettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
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
        .onAppear {
            app.refreshMeetingModelState()
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

struct QuickActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .jarvisIconGlass(tint: tint, in: Circle())
                Text(title).font(JarvisTypography.bodyEmphasis)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .jarvisContentSurface(cornerRadius: 13)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.86))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .jarvisHoverFeedback(
            in: RoundedRectangle(cornerRadius: 13, style: .continuous),
            scale: 1.008
        )
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
