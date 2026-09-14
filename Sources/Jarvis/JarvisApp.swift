import AppKit
import SwiftUI

enum JarvisApplicationPresentation {
    static let activationPolicy: NSApplication.ActivationPolicy = .regular
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
    }
}

private struct JarvisRootView: View {
    let appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    @StateObject private var mainWindowController = JarvisMainWindowController()

    var body: some View {
        ContentView()
            .environment(appModel)
            .environmentObject(appModel.resumeWorkspace)
            .tint(.accentColor)
            .jarvisTheme(
                appModel.themePreference,
                systemColorScheme: appModel.systemColorScheme
            )
            .frame(
                minWidth: JarvisMainWindowController.minimumWindowSize.width,
                minHeight: JarvisMainWindowController.minimumWindowSize.height
            )
            .overlay {
                if !appModel.hasAllRequiredPermissions {
                    JarvisPermissionGateOverlay()
                        .environment(appModel)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: appModel.hasAllRequiredPermissions)
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
            }
    }
}

@MainActor
private final class JarvisApplicationDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = JarvisMenuBarController.shared
    weak var appModel: AppModel?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(JarvisApplicationPresentation.activationPolicy)
        menuBarController.install()
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            menuBarController.reopenMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
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
