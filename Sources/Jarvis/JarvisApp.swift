import AppKit
import SwiftUI

@main
struct JarvisApp: App {
    @NSApplicationDelegateAdaptor(JarvisApplicationDelegate.self) private var applicationDelegate
    private let menuBarController = JarvisMenuBarController.shared

    var body: some Scene {
        WindowGroup("贾维斯") {
            JarvisRootView(menuBarController: menuBarController)
        }
        .defaultSize(
            width: JarvisMainWindowController.launchWindowSize.width,
            height: JarvisMainWindowController.launchWindowSize.height
        )
        .windowStyle(.hiddenTitleBar)
    }
}

private struct JarvisRootView: View {
    let menuBarController: JarvisMenuBarController

    @StateObject private var appModel = AppModel()
    @StateObject private var mainWindowController = JarvisMainWindowController()

    var body: some View {
        ContentView()
            .environmentObject(appModel)
            .tint(.accentColor)
            .jarvisTheme(
                appModel.themePreference,
                systemColorScheme: appModel.systemColorScheme
            )
            .frame(minWidth: 980, minHeight: 680)
            .background(JarvisMainWindowAccessor(controller: mainWindowController))
            .onAppear {
                menuBarController.bind(app: appModel)
            }
    }
}

@MainActor
private final class JarvisApplicationDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = JarvisMenuBarController.shared

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController.install()
    }
}
