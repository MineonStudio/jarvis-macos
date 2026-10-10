import AppKit
import SwiftUI

enum SettingsLayout {
    static let contentMaxWidth: CGFloat = 760
    static let sidebarIdealWidth: CGFloat = 200
    static let sidebarMinimumWidth: CGFloat = 180
    /// Preferred card size. Width is 70% of the previous 1040pt card.
    static let modalSize = CGSize(width: 728, height: 680)
    /// Space kept between the card and the main window so the shadow and
    /// the window edge never cover the settings sidebar.
    static let modalEdgeMargin: CGFloat = 28

    /// The card uses `modalSize` while the window is large enough. Once the
    /// window is smaller, the card shrinks to stay fully inside it.
    static func fittedModalSize(in available: CGSize) -> CGSize {
        CGSize(
            width: min(modalSize.width, max(0, available.width - modalEdgeMargin * 2)),
            height: min(modalSize.height, max(0, available.height - modalEdgeMargin * 2))
        )
    }

    /// Keeps the settings sidebar inside the card. A nested split view would
    /// otherwise borrow the main window's leading column and get clipped
    /// when that window shrinks.
    static func sidebarWidth(forModalWidth width: CGFloat) -> CGFloat {
        let minimumContentWidth: CGFloat = 280
        guard width > 0 else { return 0 }
        let fitted = min(sidebarIdealWidth, max(sidebarMinimumWidth, width - minimumContentWidth))
        return min(width, fitted)
    }
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

private enum SigningCertificatePrompt {
    case download
    case remove

    var title: String {
        switch self {
        case .download: "下载签名证书？"
        case .remove: "移除签名证书？"
        }
    }

    var message: String {
        switch self {
        case .download:
            "将在这台 Mac 的登录钥匙串中创建 Jarvis Local Signing 代码签名证书，并用它为当前安装重新签名。证书与私钥只保存在本机，不会离开这台电脑。完成后，同一安装渠道的后续更新可以沿用该签名身份，从而保留屏幕录制、辅助功能、麦克风和摄像头授权。应用会退出并重新打开。重新签名会更换代码身份，现有授权不会迁移，重新打开后需要再授予一次。"
        case .remove:
            "将从登录钥匙串中删除 Jarvis Local Signing 证书、对应私钥及其信任设置。当前已安装的副本不会被改签，已经授予的权限不会立刻失效。删除之后，后续更新无法再沿用同一签名身份；安装更新时会清除上述四项系统权限，并需要重新授权。"
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
                .fixedSize(horizontal: true, vertical: false)
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
                .fixedSize(horizontal: true, vertical: false)
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
                .fixedSize(horizontal: true, vertical: false)
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
                .fixedSize(horizontal: true, vertical: false)
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
    @State private var isClearPermissionsConfirmationPresented = false
    @State private var hasLocalSigningCertificate = false
    @State private var signingCertificatePrompt: SigningCertificatePrompt?
    @AppStorage(WallpaperSourcePreferences.storageKey)
    private var enabledWallpaperSources = WallpaperSourcePreferences.defaultStorageValue

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    JarvisSidebarNavigation(
                        topItems: SettingsSection.allCases,
                        selection: $selection,
                        title: { $0.title },
                        icon: { $0.icon },
                        headerTitle: "设置",
                        showsHeaderOrb: false
                    )
                    .frame(width: SettingsLayout.sidebarWidth(forModalWidth: proxy.size.width))
                    .frame(maxHeight: .infinity)

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.jarvisBackground)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
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
            hasLocalSigningCertificate = JarvisLocalSigning.isAvailable
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
                    versionStatusLine
                        .frame(maxWidth: .infinity, alignment: .leading)
                    updateActionButton
                }
            }
        }
    }

    /// 平时显示版本号。检查有了结果之后，结果占同一位置，版本号让开。
    private var versionStatusLine: some View {
        ZStack(alignment: .leading) {
            if let status = updateStatusText {
                Text(status)
                    .font(SettingsTypography.itemSubtitle)
                    .foregroundStyle(updateStatusColor)
                    .lineLimit(updateStatusWraps ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: updateStatusWraps)
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            } else {
                Text("Jarvis V\(JarvisAppVersion.shortVersion)")
                    .font(SettingsTypography.itemSubtitle)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: updateStatusText
        )
    }

    private var updateStatusText: String? {
        switch app.updateState {
        case .idle, .checking:
            nil
        case .upToDate:
            JarvisFeedbackCopy.latestVersion
        case let .available(release):
            "\(JarvisFeedbackCopy.updateAvailable) \(displayVersion(release.version))"
        case let .downloading(version):
            "正在下载 \(displayVersion(version))"
        case let .readyToInstall(version):
            "准备安装 \(displayVersion(version))"
        case let .installing(version):
            "正在安装 \(displayVersion(version))"
        case let .failed(message):
            message
        }
    }

    private var updateStatusColor: Color {
        if case .available = app.updateState {
            Color.jarvisAccent
        } else {
            Color.jarvisTextSecondary
        }
    }

    private var updateStatusWraps: Bool {
        if case .failed = app.updateState {
            true
        } else {
            false
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch app.updateState {
        case .checking:
            Button("检查中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case let .available(release):
            Button("下载新版本") {
                app.downloadAndInstallUpdate()
            }
            .buttonStyle(JarvisPrimaryButtonStyle())
            .accessibilityLabel("下载新版本 \(displayVersion(release.version))")
        case .downloading:
            Button("下载中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case .installing, .readyToInstall:
            Button("安装中…") {}
                .buttonStyle(JarvisSecondaryButtonStyle())
                .disabled(true)
        case .failed:
            Button("重试") {
                app.checkForUpdates()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        case .idle, .upToDate:
            Button("检查更新") {
                app.checkForUpdates()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
        }
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
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var appIconSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                SettingsCardHeader(title: "应用图标", systemImage: "square.grid.2x2.fill")
                Spacer(minLength: 8)
                JarvisAppIconPicker(selection: Binding(
                    get: { app.appIconAppearance },
                    set: { app.updateAppIconAppearance($0) }
                ))
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var accentColorSettingsCard: some View {
        JarvisCard {
            HStack(spacing: 14) {
                SettingsCardHeader(title: "强调色", systemImage: "paintpalette")
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                JarvisAccentColorPicker(selection: Binding(
                    get: { app.accentColorPreference },
                    set: { app.updateAccentColorPreference($0) }
                ))
                .frame(maxWidth: .infinity, alignment: .trailing)
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
                .jarvisSwitchAccent()
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
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
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
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }

    private var permissionSettingsCard: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    SettingsCardHeader(title: "权限", systemImage: "lock.shield")
                    Spacer(minLength: 8)
                    Button(hasLocalSigningCertificate ? "移除证书" : "下载证书") {
                        signingCertificatePrompt = hasLocalSigningCertificate ? .remove : .download
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .confirmationDialog(
                        signingCertificatePrompt?.title ?? "",
                        isPresented: Binding(
                            get: { signingCertificatePrompt != nil },
                            set: {
                                if !$0 {
                                    signingCertificatePrompt = nil
                                }
                            }
                        ),
                        titleVisibility: .visible
                    ) {
                        if signingCertificatePrompt == .download {
                            Button("下载并重启") {
                                app.installLocalSigningCertificate()
                            }
                        } else if signingCertificatePrompt == .remove {
                            Button("移除证书", role: .destructive) {
                                app.removeLocalSigningCertificate()
                                hasLocalSigningCertificate = JarvisLocalSigning.isAvailable
                            }
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text(signingCertificatePrompt?.message ?? "")
                    }
                    Button("清除所有权限") {
                        isClearPermissionsConfirmationPresented = true
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
                }
                JarvisPermissionList(cornerRadius: 12, mode: .settings)
            }
        }
        .confirmationDialog(
            "清除所有权限？",
            isPresented: $isClearPermissionsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("确认并重启", role: .destructive) {
                app.clearAllPrivacyPermissionsAndRestart()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除屏幕录制、辅助功能、麦克风和摄像头授权，然后重新打开贾维斯。")
        }
    }
}

struct SettingsModalOverlay: View {
    @Binding var isPresented: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let fitted = SettingsLayout.fittedModalSize(in: proxy.size)
            ZStack {
                // 模糊由窗口上的 NSGlassEffectView 绘制。这里只接住点击，
                // 避免再叠一层材质把系统玻璃盖住。
                Color.clear
                    .contentShape(Rectangle())

                SettingsView {
                    isPresented = false
                }
                .frame(width: fitted.width, height: fitted.height)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.30), radius: 34, y: 18)
                .transition(JarvisMotion.contentTransition(reduceMotion: reduceMotion))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .bottom) {
                JarvisToastHost(message: app.toastMessage)
                    .padding(.bottom, 26)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onExitCommand {
            isPresented = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置")
    }
}

/// Installs the settings card above the window's AppKit sidebar and toolbar.
/// Those views are outside the SwiftUI overlay order, so hiding them was the
/// only way to keep the card visible, and that reflowed the main window.
struct SettingsOverlayAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    /// Passed in directly. Reading `@Environment` here crashes while AppKit
    /// builds the key-view loop, before that environment value is installed.
    let app: AppModel

    func makeCoordinator() -> SettingsOverlayAnchorView {
        SettingsOverlayAnchorView()
    }

    func makeNSView(context: Context) -> SettingsOverlayAnchorView {
        context.coordinator
    }

    func updateNSView(_ anchor: SettingsOverlayAnchorView, context _: Context) {
        anchor.update(isPresented: isPresented, app: app) {
            isPresented = $0
        }
    }
}

final class SettingsOverlayAnchorView: NSView {
    private var presented = false
    private var app: AppModel?
    private var setPresented: ((Bool) -> Void)?
    private var container: SettingsOverlayContainer?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            sync()
        }
    }

    func update(isPresented: Bool, app: AppModel, setPresented: @escaping (Bool) -> Void) {
        presented = isPresented
        self.app = app
        self.setPresented = setPresented
        sync()
    }

    private func sync() {
        guard presented, let app, setPresented != nil, let parent = overlayParent else {
            container?.dismiss()
            return
        }

        let container = self.container ?? SettingsOverlayContainer()
        self.container = container
        let binding = Binding<Bool>(
            get: { [weak self] in
                self?.presented ?? false
            },
            set: { [weak self] newValue in
                self?.presented = newValue
                self?.setPresented?(newValue)
            }
        )
        container.present(isPresented: binding, app: app, in: parent)
    }

    private var overlayParent: NSView? {
        guard let contentView = window?.contentView else { return nil }
        return contentView.superview ?? contentView
    }
}

private struct SettingsOverlayRoot: View {
    @Binding var isPresented: Bool
    let app: AppModel

    var body: some View {
        SettingsModalOverlay(isPresented: $isPresented)
            .environment(app)
            .tint(app.accentColorPreference.resolvedColor)
            .accentColor(app.accentColorPreference.resolvedColor)
            .jarvisTheme(app.themePreference, systemColorScheme: app.systemColorScheme)
    }
}

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    /// SwiftUI's first layout pass sizes a hosting view to the card. That pass
    /// was shrinking the main window the first time settings opened.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(lockedSize ?? newSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clearBacking()
    }

    override func layout() {
        super.layout()
        clearBacking()
    }

    /// Fill the overlay. A proposal smaller than the overlay is the fitting pass.
    private var lockedSize: NSSize? {
        guard let container = superview else { return nil }
        let size = container.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }
        return size
    }

    private func clearBacking() {
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// WebKit decides whether the page is under the pointer by hit-testing
/// `window.contentView` only. The settings glass is a sibling of that view,
/// so the page still sees the pointer through the scrim.
enum SettingsBackdropLock {
    nonisolated(unsafe) static var isActive = false
}

private final class SettingsOverlayContainer: NSView {
    /// System Settings → 外观 → Liquid Glass. `.clear` is the lighter system
    /// preset and still follows that slider. `.regular` on a full window reads
    /// as a heavy frost, and a material plus a black dim does not follow it.
    private let scrim = NSGlassEffectView(frame: .zero)
    private let hosting = ClearHostingView(rootView: AnyView(Color.clear))
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var isBringingToFront = false
    private var isInstalled = false

    override var isOpaque: Bool {
        false
    }

    init() {
        super.init(frame: .zero)
        scrim.style = .clear
        scrim.cornerRadius = 0
        scrim.translatesAutoresizingMaskIntoConstraints = true
        scrim.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.translatesAutoresizingMaskIntoConstraints = true
        // Keep the glass view outside a layer-backed parent so its backdrop
        // samples the main window instead of an empty container layer.
        addSubview(scrim)
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    /// Glass hit-testing returns the page underneath the scrim. Keep those
    /// events here so the window behind the settings card cannot scroll or
    /// activate. Traffic-light buttons stay outside this view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint), !coversWindowButton(at: localPoint) else { return nil }
        if let hit = hosting.hitTest(localPoint), hit.isDescendant(of: hosting) {
            return hit
        }
        return self
    }

    override func mouseDown(with _: NSEvent) {}

    override func mouseUp(with _: NSEvent) {}

    override func mouseDragged(with _: NSEvent) {}

    override func rightMouseDown(with _: NSEvent) {}

    override func rightMouseUp(with _: NSEvent) {}

    override func rightMouseDragged(with _: NSEvent) {}

    override func otherMouseDown(with _: NSEvent) {}

    override func otherMouseUp(with _: NSEvent) {}

    override func otherMouseDragged(with _: NSEvent) {}

    override func scrollWheel(with _: NSEvent) {}

    override func magnify(with _: NSEvent) {}

    override func rotate(with _: NSEvent) {}

    override func swipe(with _: NSEvent) {}

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        installObservers()
        bringToFront()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            removeObservers()
        }
    }

    override func layout() {
        super.layout()
        if let superview, frame != superview.bounds {
            frame = superview.bounds
        }
        scrim.frame = bounds
        hosting.frame = bounds
        bringToFront()
    }

    func present(isPresented: Binding<Bool>, app: AppModel, in parent: NSView) {
        SettingsBackdropLock.isActive = true
        installEventMonitor()
        // Replacing rootView resets the settings selection, so install it once per open.
        let installing = !isInstalled
        // Size to the window before the SwiftUI tree is installed, so its first
        // layout sees the real window instead of the card's ideal size.
        frame = parent.bounds
        scrim.frame = bounds
        hosting.frame = bounds
        if superview !== parent {
            autoresizingMask = [.width, .height]
            parent.addSubview(self, positioned: .above, relativeTo: nil)
        }
        if installing {
            hosting.sizingOptions = []
            hosting.safeAreaRegions = []
            hosting.rootView = AnyView(
                SettingsOverlayRoot(isPresented: isPresented, app: app)
            )
            hosting.sizingOptions = []
            isInstalled = true
        }
        bringToFront()
        guard installing else { return }
        window?.makeFirstResponder(hosting)
    }

    func dismiss() {
        guard superview != nil || isInstalled else { return }
        SettingsBackdropLock.isActive = false
        removeEventMonitor()
        isInstalled = false
        hosting.rootView = AnyView(Color.clear)
        removeFromSuperview()
    }

    /// Events over the glass never reach the page. The settings card and the
    /// window buttons still receive theirs.
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                .scrollWheel, .magnify, .swipe, .rotate, .mouseMoved
            ]
        ) { [weak self] event in
            guard let self, SettingsBackdropLock.isActive, event.window === self.window else {
                return event
            }
            if self.shouldPassThroughScrim(event) {
                return event
            }
            NSCursor.arrow.set()
            return nil
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func shouldPassThroughScrim(_ event: NSEvent) -> Bool {
        let localPoint = convert(event.locationInWindow, from: nil)
        if coversWindowButton(at: localPoint) {
            return true
        }
        let fitted = SettingsLayout.fittedModalSize(in: bounds.size)
        let card = CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        ).insetBy(dx: -8, dy: -8)
        return card.contains(localPoint)
    }

    private func bringToFront() {
        guard !isBringingToFront, let superview, superview.subviews.last !== self else { return }
        isBringingToFront = true
        superview.addSubview(self, positioned: .above, relativeTo: nil)
        isBringingToFront = false
    }

    private func coversWindowButton(at localPoint: NSPoint) -> Bool {
        guard let window else { return false }
        let windowPoint = convert(localPoint, to: nil)
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return buttons.contains { kind in
            guard let button = window.standardWindowButton(kind), let buttonParent = button.superview else {
                return false
            }
            let local = buttonParent.convert(windowPoint, from: nil)
            return button.frame.insetBy(dx: -4, dy: -4).contains(local)
        }
    }

    private func installObservers() {
        removeObservers()
        guard let window else { return }
        let center = NotificationCenter.default
        let resizeNames: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification
        ]
        for name in resizeNames {
            observers.append(
                center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.bringToFront()
                    }
                }
            )
        }
        observers.append(
            center.addObserver(
                forName: NSSplitView.didResizeSubviewsNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.bringToFront()
                }
            }
        )
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
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
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 8)
                action
                    .fixedSize(horizontal: true, vertical: false)
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
            if stage == .chineseTranscription {
                Text("系统已安装")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
            } else {
                Button("移除", role: .destructive) {
                    app.removeMeetingModel(stage)
                }
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
                .disabled(!app.canManageMeetingModels)
                .help("移除本机下载的 \(stage.title) 模型")
            }
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
                .fixedSize(horizontal: true, vertical: false)
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

    var body: some View {
        JarvisSegmentedControl(
            items: Array(JarvisAppIconAppearance.allCases),
            selection: $selection
        ) { appearance, isSelected in
            Text(appearance.title)
                .font(JarvisTypography.controlEmphasis)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .fixedSize(horizontal: true, vertical: false)
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

struct JarvisAccentColorPicker: View {
    @Binding var selection: JarvisAccentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredAccent: JarvisAccentColor?

    /// 色块中心距。截图里九颗圆按 36pt 排开，不随卡片变宽被拉开。
    private static let pitch: CGFloat = 36
    /// 跟上面应用图标那条分段控件一样高，色块在这行里垂直居中。
    private static var controlHeight: CGFloat {
        JarvisMetrics.segmentedItemHeight
            + JarvisMetrics.segmentedItemVerticalPadding * 2
            + JarvisMetrics.segmentedControlPadding * 2
    }

    private var accents: [JarvisAccentColor] {
        Array(JarvisAccentColor.allCases)
    }

    var body: some View {
        GeometryReader { proxy in
            let pitch = fittedPitch(in: proxy.size.width)
            HStack(spacing: 0) {
                ForEach(accents) { accent in
                    accentTab(accent, pitch: pitch)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .frame(height: Self.controlHeight)
        .animation(
            JarvisMotion.animation(JarvisMotion.selection, reduceMotion: reduceMotion),
            value: selection
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.hover, reduceMotion: reduceMotion),
            value: hoveredAccent
        )
    }

    /// 宽够用时保持 36pt。标题必须留在一行里，窄的时候只把色块间距收回去。
    private func fittedPitch(in available: CGFloat) -> CGFloat {
        let count = CGFloat(accents.count)
        guard available > 1 else { return Self.pitch }
        return min(Self.pitch, max(AccentColorSwatch.slot, available / count))
    }

    private func accentTab(_ accent: JarvisAccentColor, pitch: CGFloat) -> some View {
        let isSelected = selection == accent
        return Button {
            selection = accent
        } label: {
            AccentColorSwatch(accent: accent, isSelected: isSelected)
                .overlay(alignment: .top) {
                    Text(accent.title)
                        .font(JarvisTypography.caption)
                        // 系统设置里这行名称大约是 42% 的黑，比 secondary 更浅。
                        .foregroundStyle(Color.primary.opacity(0.42))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(y: AccentColorSwatch.slot + 2)
                        .opacity(hoveredAccent == accent ? 1 : 0)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.9))
        .frame(width: pitch, height: Self.controlHeight)
        .accessibilityLabel("强调色：\(accent.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering in
            if isHovering {
                hoveredAccent = accent
            } else if hoveredAccent == accent {
                hoveredAccent = nil
            }
        }
    }
}

/// 未选中是一颗实心圆。选中时圆的大小不变，外面加一圈同色环，环和圆之间露出底色。
/// 跟随系统不是单一颜色，用色轮表示。
private struct AccentColorSwatch: View {
    let accent: JarvisAccentColor
    var isSelected: Bool

    static let diameter: CGFloat = 24
    static let ringLineWidth: CGFloat = 2
    static let ringGap: CGFloat = 2
    static var slot: CGFloat {
        diameter + (ringLineWidth + ringGap) * 2
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ringColor, lineWidth: Self.ringLineWidth)
                .opacity(isSelected ? 1 : 0)
            Circle()
                .fill(fill)
                .padding(Self.ringLineWidth + Self.ringGap)
        }
        .frame(width: Self.slot, height: Self.slot)
        .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        if accent == .system {
            AnyShapeStyle(Self.wheel)
        } else {
            AnyShapeStyle(accent.color)
        }
    }

    private var ringColor: Color {
        if accent == .system {
            Color(nsColor: .controlAccentColor)
        } else {
            accent.color
        }
    }

    private static let wheel = AngularGradient(
        colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
        center: .center
    )
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
