import AppKit
import SwiftUI

struct ShortcutSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var screenshotShortcut = ScreenshotShortcut.default
    @State private var clipboardShortcut = ScreenshotShortcut.clipboardDefault
    @State private var isRecordingScreenshotShortcut = false
    @State private var isRecordingClipboardShortcut = false

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("快捷键", systemImage: "keyboard")
                    .font(JarvisTypography.bodyEmphasis)

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
            }
        }
        .onAppear {
            screenshotShortcut = app.screenshotShortcut
            clipboardShortcut = app.clipboardShortcut
            _ = app.validateScreenshotShortcut(screenshotShortcut)
            _ = app.validateClipboardShortcut(clipboardShortcut)
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

struct ScreenshotTranslationSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var apiKey = ""

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ScreenshotTranslationIcon(isSelected: false)
                    Text("配置 API")
                        .font(JarvisTypography.bodyEmphasis)
                }

                HStack(spacing: 10) {
                    Text("接口地址")
                        .font(JarvisTypography.control)
                        .frame(width: 70, alignment: .leading)
                    TextField(
                        ScreenshotTranslationConfiguration.defaultEndpoint,
                        text: Binding(
                            get: { app.screenshotTranslationEndpoint },
                            set: { app.updateScreenshotTranslationEndpoint($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(app.screenshotTranslationSettingsLocked)
                }

                HStack(spacing: 10) {
                    Text("模型")
                        .font(JarvisTypography.control)
                        .frame(width: 70, alignment: .leading)
                    TextField(
                        ScreenshotTranslationConfiguration.defaultModel,
                        text: Binding(
                            get: { app.screenshotTranslationModel },
                            set: { app.updateScreenshotTranslationModel($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(app.screenshotTranslationSettingsLocked)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("API Key")
                        .font(JarvisTypography.control)
                        .frame(width: 70, alignment: .leading)
                    SecureField(
                        app.screenshotTranslationAPIKeyMask.isEmpty
                            ? "输入 API Key"
                            : app.screenshotTranslationAPIKeyMask,
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(app.screenshotTranslationSettingsLocked)
                    Button("保存") {
                        guard app.saveScreenshotTranslationAPIKey(apiKey) else { return }
                        apiKey = ""
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(
                        app.screenshotTranslationSettingsLocked
                            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    if app.screenshotTranslationSettingsLocked {
                        Button("编辑") {
                            app.editScreenshotTranslationSettings()
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                versionAndUpdateCard

                themeSettingsCard

                launchAtLoginSettingsCard
                ClipboardCacheSettingsCard()

                ScreenshotTranslationSettingsCard()

                ShortcutSettingsCard()
            }
            .padding(JarvisMetrics.pageInset)
        }
    }

    private var themeSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                Label("主题", systemImage: "circle.lefthalf.filled")
                    .font(JarvisTypography.bodyEmphasis)
                Spacer()
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
                Label("开机自启", systemImage: "power")
                    .font(JarvisTypography.cardTitle)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { app.launchAtLoginEnabled },
                    set: { app.updateLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    private var versionAndUpdateCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Label("版本与更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(JarvisTypography.bodyEmphasis)
                    Text("(v\(JarvisAppVersion.shortVersion))")
                        .font(JarvisTypography.monospaced)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer()
                updateControls
            }
            .frame(height: 34)
        }
    }

    private var updateControls: some View {
        Group {
            switch app.updateState {
            case let .available(release):
                HStack(spacing: 10) {
                    Text(release.version)
                        .font(JarvisTypography.monospaced)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                    Button("下载最新版") {
                        app.downloadAndInstallUpdate()
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                }
            case .checking:
                HStack(spacing: 8) {
                    updateStatusLabel
                    ProgressView()
                        .controlSize(.small)
                }
            case .downloading, .installing:
                HStack(spacing: 8) {
                    updateStatusLabel
                    ProgressView()
                        .controlSize(.small)
                }
            default:
                HStack(spacing: 10) {
                    updateStatusLabel
                    Button(updateActionTitle) {
                        app.checkForUpdates()
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(isUpdating)
                }
            }
        }
        .frame(height: 34, alignment: .center)
    }

    private var updateStatusLabel: some View {
        Group {
            switch app.updateState {
            case .idle:
                EmptyView()
            case .checking:
                Text("正在检查更新…")
            case .upToDate:
                EmptyView()
            case let .available(release):
                Text("发现新版本 \(release.version)")
                    .foregroundStyle(Color.accentColor)
            case let .downloading(version):
                Text("正在下载 \(version)…")
            case let .installing(version):
                Text("正在安装 \(version)…")
            case let .failed(message):
                Text(message)
            }
        }
        .font(JarvisTypography.caption)
        .foregroundStyle(Color.jarvisTextSecondary)
        .lineLimit(1)
    }

    private var updateActionTitle: String {
        if case .failed = app.updateState {
            return "重新检查"
        }
        return "检查更新"
    }

    private var isUpdating: Bool {
        switch app.updateState {
        case .checking, .downloading, .installing: true
        default: false
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
            .jarvisGlass(cornerRadius: 13)
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
