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
    @StateObject private var appModel: AppModel

    init() {
        NSApplication.shared.setActivationPolicy(JarvisApplicationPresentation.activationPolicy)

        let appModel = AppModel()
        _appModel = StateObject(wrappedValue: appModel)
        // Bind before the status item is installed. Menu actions must remain
        // usable even when the main window has not appeared yet.
        menuBarController.bind(app: appModel)
    }

    var body: some Scene {
        WindowGroup(JarvisAppIdentity.displayName, id: JarvisAppIdentity.mainWindowSceneID) {
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
    @ObservedObject var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    @StateObject private var mainWindowController = JarvisMainWindowController()

    var body: some View {
        ContentView()
            .environmentObject(appModel)
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

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(JarvisApplicationPresentation.activationPolicy)
        JarvisFreshInstallPermissionCleanup.runIfNeeded()
        menuBarController.install()
    }
}
