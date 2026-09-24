import AppKit
import SwiftUI

enum JarvisApplicationPresentation {
    static let activationPolicy: NSApplication.ActivationPolicy = .regular
    static let terminateAfterLastWindowClosed = false
}

@main
@MainActor
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(JarvisApplicationDelegate.self) private var applicationDelegate
    private let menuBarController = JarvisMenuBarController.shared
    @State private var appModel: AppModel
    private let mainThreadHealthMonitor = MainThreadHealthMonitor()
    private let memoryPressureMonitor: JarvisMemoryPressureMonitor

    init() {
        NSApplication.shared.setActivationPolicy(JarvisApplicationPresentation.activationPolicy)
        JarvisLog.notice(
            category: .lifecycle,
            event: "process.started",
            fields: [
                "processID": String(ProcessInfo.processInfo.processIdentifier),
                "bundlePath": JarvisLogRedactor.path(Bundle.main.bundleURL.path)
            ]
        )

        let appModel = AppModel()
        _appModel = State(initialValue: appModel)
        memoryPressureMonitor = JarvisMemoryPressureMonitor {
            Task { @MainActor in
                JarvisThumbnailCache.purge()
                ClipboardItemPreview.purgeVideoThumbnailCache()
                WallpaperImageLoader.purgeCache()
            }
        }
        mainThreadHealthMonitor.start()
        JarvisPerformance.emit("application initialized")
        // Bind before the status item is installed. Menu actions must remain
        // usable even when the main window has not appeared yet.
        menuBarController.bind(app: appModel)
        applicationDelegate.appModel = appModel
    }

    var body: some Scene {
        Window(JarvisAppIdentity.displayName, id: JarvisAppIdentity.mainWindowSceneID) {
            JarvisRootView(appModel: appModel)
        }
        .defaultSize(
            width: JarvisMainWindowController.launchWindowSize.width,
            height: JarvisMainWindowController.launchWindowSize.height
        )
        .windowToolbarStyle(.unified)
        // Keep native menu titles inline in the toolbar. macOS 27's
        // titleAndIcon style moves them below their circular trigger.
        .windowToolbarLabelStyle(fixed: .titleOnly)
    }
}

private struct JarvisRootView: View {
    let appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    @StateObject private var mainWindowController = JarvisMainWindowController()
    @State private var isSettingsPresented = false

    var body: some View {
        ContentView(isSettingsPresented: $isSettingsPresented)
            .environment(appModel)
            .environmentObject(appModel.resumeWorkspace)
            .tint(appModel.accentColorPreference.resolvedColor)
            .accentColor(appModel.accentColorPreference.resolvedColor)
            .jarvisTheme(
                appModel.themePreference,
                systemColorScheme: appModel.systemColorScheme
            )
            .frame(
                minWidth: JarvisMainWindowController.minimumWindowSize.width,
                minHeight: JarvisMainWindowController.minimumWindowSize.height
            )
            .overlay {
                if let prompt = appModel.taskPermissionPrompt, !isSettingsPresented {
                    JarvisTaskPermissionOverlay(prompt: prompt)
                        .environment(appModel)
                }
            }
            .overlay {
                if isSettingsPresented {
                    SettingsModalOverlay(isPresented: $isSettingsPresented)
                        .environment(appModel)
                }
            }
            .overlay(alignment: .bottom) {
                JarvisToastHost(message: appModel.toastMessage)
                    .padding(.bottom, 26)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.2), value: appModel.taskPermissionPrompt)
            .animation(.easeInOut(duration: 0.2), value: isSettingsPresented)
            // The settings overlay is a focused surface; keep the main window's
            // module toolbar from showing through above it.
            .toolbarVisibility(isSettingsPresented ? .hidden : .visible, for: .windowToolbar)
            // Keep the system title-bar region and its native window controls.
            // Apple recommends removing only the title and toolbar background
            // when content should extend beneath that region.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .background(JarvisMainWindowAccessor(controller: mainWindowController))
            .background(JarvisFirstFrameProbe().frame(width: 1, height: 1))
            .onAppear {
                appModel.refreshPermissionStatus()
                JarvisMenuBarController.shared.bind {
                    openWindow(id: JarvisAppIdentity.mainWindowSceneID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                appModel.refreshPermissionStatus()
                if let prompt = appModel.taskPermissionPrompt,
                   appModel.isRequiredPermissionGranted(prompt.permission)
                {
                    appModel.taskPermissionPrompt = nil
                }
            }
    }
}

@MainActor
private final class JarvisApplicationDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = JarvisMenuBarController.shared
    private let instanceCoordinator = JarvisInstanceCoordinator()
    private var screenParametersObserver: (any NSObjectProtocol)?
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(JarvisApplicationPresentation.activationPolicy)
        menuBarController.install()
        NSApp.activate()
        // 挂在委托上而不是主窗口上：主窗口关着时贴图也可能还在。
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.appModel?.handleScreenParametersChange()
            }
        }
        JarvisLog.info(
            category: .lifecycle,
            event: "application.didFinishLaunching"
        )
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        JarvisLog.info(
            category: .window,
            event: "application.reopen",
            fields: ["hasVisibleWindows": String(flag)]
        )
        if !flag {
            menuBarController.reopenMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        JarvisApplicationPresentation.terminateAfterLastWindowClosed
    }

    func applicationWillTerminate(_: Notification) {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
        JarvisLog.notice(category: .lifecycle, event: "application.willTerminate")
        // 日志写入是异步批量的，退出前把还没落盘的事件写完。
        JarvisLog.flush()
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard let appModel else { return .terminateNow }

        if appModel.meetingCurrentRecordingID != nil {
            let alert = NSAlert()
            alert.messageText = "正在录音"
            alert.informativeText = "退出将停止录音并保留已写入的原始音频。转写不会在退出时继续，可稍后重新处理。"
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "停止录音并退出")
            guard alert.runModal() != .alertFirstButtonReturn else {
                return .terminateCancel
            }
            Task { @MainActor in
                await appModel.finalizeMeetingRecordingForTermination()
                NSApp.reply(toApplicationShouldTerminate: Self.confirmResumeDiscardIfNeeded(appModel))
            }
            return .terminateLater
        }

        return Self.confirmResumeDiscardIfNeeded(appModel) ? .terminateNow : .terminateCancel
    }

    private static func confirmResumeDiscardIfNeeded(_ appModel: AppModel) -> Bool {
        guard appModel.resumeWorkspace.requiresSaveBeforeNewResume else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "简历尚未保存"
        alert.informativeText = "退出后未保存的简历内容会丢失。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "不保存并退出")
        return alert.runModal() != .alertFirstButtonReturn
    }
}
