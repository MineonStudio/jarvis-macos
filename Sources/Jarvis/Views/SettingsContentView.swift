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
                    .font(.system(size: 14, weight: .semibold))

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
                .font(.system(size: 13, weight: .semibold))
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
    @EnvironmentObject private var app: AppModel
    @State private var apiKey = ""

    private let maskedAPIKey = "••••••••••••••••"

    private var modelConfigurationSaved: Bool {
        app.isModelConfigurationSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                versionAndUpdateCard

                themeSettingsCard

                screenshotTranslationSettingsCard

                JarvisCard {
                    VStack(alignment: .leading, spacing: 15) {
                        Label("模型 API", systemImage: "brain.head.profile")
                            .font(.system(size: 15, weight: .semibold))

                        LabeledSetting(title: "Provider") {
                            TextField("OpenAI Compatible", text: $app.modelConfiguration.providerName)
                                .textFieldStyle(.roundedBorder)
                        }
                        .disabled(modelConfigurationSaved)
                        .opacity(modelConfigurationSaved ? 0.58 : 1)
                        LabeledSetting(title: "API Base URL") {
                            TextField("https://api.openai.com/v1", text: $app.modelConfiguration.baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        .disabled(modelConfigurationSaved)
                        .opacity(modelConfigurationSaved ? 0.58 : 1)
                        LabeledSetting(title: "模型名称") {
                            TextField("gpt-4o-mini", text: $app.modelConfiguration.modelName)
                                .textFieldStyle(.roundedBorder)
                        }
                        .disabled(modelConfigurationSaved)
                        .opacity(modelConfigurationSaved ? 0.58 : 1)
                        LabeledSetting(title: "API Key") {
                            apiKeyField
                        }
                        .opacity(modelConfigurationSaved ? 0.58 : 1)

                        HStack(spacing: 10) {
                            Spacer()
                            if !modelConfigurationSaved {
                                Button("保存配置") {
                                    app.saveModelSettings(apiKey: apiKey)
                                    apiKey = ""
                                }
                                .buttonStyle(JarvisPrimaryButtonStyle())
                            }
                            Button("编辑配置") {
                                app.editModelSettings()
                            }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                            .disabled(!modelConfigurationSaved)
                            Button("测试连接") {
                                app.testConnection(apiKeyOverride: apiKey)
                            }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                        }
                    }
                }

                ShortcutSettingsCard()
            }
            .padding(JarvisMetrics.pageInset)
        }
        .onAppear {
            apiKey = ""
        }
    }

    @ViewBuilder
    private var apiKeyField: some View {
        if app.hasAPIKey {
            Text(maskedAPIKey)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.jarvisTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
                }
        } else {
            SecureField("sk-…", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(modelConfigurationSaved)
        }
    }

    private var themeSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                Label("主题", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                JarvisThemePicker(selection: Binding(
                    get: { app.themePreference },
                    set: { app.updateThemePreference($0) }
                ))
            }
        }
    }

    private var screenshotTranslationSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                Label("截图翻译", systemImage: "character.bubble")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Picker("翻译为", selection: Binding(
                    get: { app.targetLanguage },
                    set: { app.updateTranslationLanguage($0) }
                )) {
                    ForEach(ScreenshotTranslationLanguage.allCases) { language in
                        Text(language.rawValue).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .trailing)
            }
        }
    }

    private var versionAndUpdateCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Label("版本与更新", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Text("(v\(JarvisAppVersion.shortVersion))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
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
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                Text("已是最新版本")
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
        .font(.system(size: 10))
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
        HStack(spacing: 2) {
            ForEach(JarvisTheme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    Text(theme.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == theme ? Color.white : Color.secondary)
                        .frame(minWidth: 54, minHeight: 28)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Capsule())
                        .background(
                            selection == theme ? Color.accentColor.opacity(0.82) : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            }
        }
        .padding(2)
        .jarvisGlass(in: Capsule(), interactive: false)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Button {
            app.captureScreenshot()
        } label: {
            Label("框选截图", systemImage: "viewfinder")
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            app.selectedSection = .overview
        } label: {
            Label("打开贾维斯", systemImage: "rectangle.on.rectangle")
        }
        Button {
            app.showClipboardPanel()
        } label: {
            Label("打开剪贴板（\(app.clipboardShortcut.displayString)）", systemImage: "clipboard")
        }
        Divider()
        Text(app.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("退出贾维斯", systemImage: "power")
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
                Text(title).font(.system(size: 13, weight: .semibold))
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
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct JarvisToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
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

struct StatusPill: View {
    let text: String
    let color: Color
    let usesTint: Bool

    private var label: some View {
        Label(text, systemImage: "circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
    }

    var body: some View {
        if usesTint {
            label.jarvisGlass(tint: color.opacity(0.18), in: Capsule(), interactive: false)
        } else {
            // Keep the unconfigured state neutral. A full secondary tint
            // makes the status badge look like a dark filled control.
            label.jarvisGlass(in: Capsule(), interactive: false)
        }
    }
}

struct LabeledSetting<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(Color.jarvisTextSecondary)
            content
        }
    }
}
