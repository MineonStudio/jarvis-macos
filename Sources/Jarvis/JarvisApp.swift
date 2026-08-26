import AppKit
import SwiftUI

@main
@MainActor
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(JarvisApplicationDelegate.self) private var applicationDelegate
    private let menuBarController = JarvisMenuBarController.shared
    @StateObject private var appModel: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)

        let appModel = AppModel()
        _appModel = StateObject(wrappedValue: appModel)
        // Bind before the status item is installed. Menu actions must remain
        // usable even when the main window has not appeared yet.
        menuBarController.bind(app: appModel)
    }

    var body: some Scene {
        WindowGroup("贾维斯") {
            JarvisRootView(menuBarController: menuBarController, appModel: appModel)
        }
        .defaultSize(
            width: JarvisMainWindowController.launchWindowSize.width,
            height: JarvisMainWindowController.launchWindowSize.height
        )
        .windowToolbarStyle(.unified)
    }
}

private struct JarvisRootView: View {
    let menuBarController: JarvisMenuBarController
    @ObservedObject var appModel: AppModel

    @StateObject private var mainWindowController = JarvisMainWindowController()

    var body: some View {
        ContentView()
            .environmentObject(appModel)
            .tint(.accentColor)
            .jarvisTheme(
                appModel.themePreference,
                systemColorScheme: appModel.systemColorScheme
            )
            .frame(minWidth: 480, minHeight: 360)
            // Keep the system title-bar region and its native window controls.
            // Apple recommends removing only the title and toolbar background
            // when content should extend beneath that region.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .background(JarvisMainWindowAccessor(controller: mainWindowController))
    }
}

@MainActor
private final class JarvisApplicationDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = JarvisMenuBarController.shared

    func applicationDidFinishLaunching(_: Notification) {
        NSLog("Jarvis applicationDidFinishLaunching isRunning=\(NSApp.isRunning)")
        NSApp.setActivationPolicy(.accessory)
        JarvisFreshInstallPermissionCleanup.runIfNeeded()
        DispatchQueue.main.async { [weak self] in
            NSLog("Jarvis scheduling menu bar install isRunning=\(NSApp.isRunning)")
            self?.menuBarController.install()
        }
    }
}
