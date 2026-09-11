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
            // Keep the system title-bar region and its native window controls.
            // Apple recommends removing only the title and toolbar background
            // when content should extend beneath that region.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .background(JarvisMainWindowAccessor(controller: mainWindowController))
            .background(JarvisFirstFrameProbe().frame(width: 1, height: 1))
            .onAppear {
                JarvisMenuBarController.shared.bind {
                    openWindow(id: JarvisAppIdentity.mainWindowSceneID)
                }
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

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard let workspace = appModel?.resumeWorkspace, workspace.requiresSaveBeforeNewResume else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "简历尚未保存"
        alert.informativeText = "退出后未保存的简历内容会丢失。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "不保存并退出")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
}
