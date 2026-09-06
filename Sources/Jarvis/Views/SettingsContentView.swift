import AppKit
import SwiftUI

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
    @State private var isRecordingScreenshotShortcut = false
    @State private var isRecordingClipboardShortcut = false

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
                        HermesSettingsCard()
                        ClipboardCacheSettingsCard()

                        ScreenshotLanguagePackSettingsCard()

                        ShortcutSettingsCard()

                        permissionStatusRow
                    }
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

    private var permissionStatusRow: some View {
        HStack(spacing: 10) {
            SettingsPermissionCapsule(
                title: "屏幕录制",
                isGranted: app.screenCapturePermissionGranted,
                action: { _ = app.requestScreenCapturePermission() }
            )
            SettingsPermissionCapsule(
                title: "辅助功能",
                isGranted: app.accessibilityPermissionGranted,
                action: app.requestAccessibilityPermission
            )
            SettingsPermissionCapsule(
                title: "麦克风",
                isGranted: app.microphonePermissionGranted,
                action: app.requestMicrophonePermission
            )
            SettingsPermissionCapsule(
                title: "摄像头",
                isGranted: app.cameraPermissionGranted,
                action: app.requestCameraPermission
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
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

private struct SettingsPermissionCapsule: View {
    let title: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(Color.primary)
                Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isGranted ? Color.green : Color.orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill((isGranted ? Color.green : Color.orange).opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke((isGranted ? Color.green : Color.orange).opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isGranted)
        .accessibilityLabel("\(title)，\(isGranted ? "已授权" : "需要授权")")
        .help(isGranted ? "\(title)已授权" : "点击获取\(title)权限")
    }
}
