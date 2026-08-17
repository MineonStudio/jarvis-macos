import AppKit
import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var mainWindowController = JarvisMainWindowController()

    var body: some Scene {
        WindowGroup("贾维斯") {
            ContentView()
                .environmentObject(appModel)
                .tint(.accentColor)
                .jarvisTheme(
                    appModel.themePreference,
                    systemColorScheme: appModel.systemColorScheme
                )
                .frame(minWidth: 980, minHeight: 680)
                .background(JarvisMainWindowAccessor(controller: mainWindowController))
        }
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appModel)
                .jarvisTheme(
                    appModel.themePreference,
                    systemColorScheme: appModel.systemColorScheme
                )
        } label: {
            Text("JARVIS")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.primary)
                .fixedSize()
                .accessibilityLabel("贾维斯")
                .help("贾维斯")
        }
    }
}
