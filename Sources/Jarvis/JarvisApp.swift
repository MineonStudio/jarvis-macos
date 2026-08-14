import AppKit
import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var appModel = AppModel()

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
                .background(JarvisMainWindowChrome())
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

/// Makes the main window's native titlebar share the same visual plane as the
/// SwiftUI content while keeping the standard macOS window controls.
private struct JarvisMainWindowChrome: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .textBackgroundColor
        window.sharingType = .readOnly

        if let close = window.standardWindowButton(.closeButton),
           let miniaturize = window.standardWindowButton(.miniaturizeButton),
           let zoom = window.standardWindowButton(.zoomButton)
        {
            // The native traffic lights belong to the sidebar in the reference
            // layout, so move the standard button group into that column.
            let titlebarY = close.frame.minY
            close.setFrameOrigin(NSPoint(x: 18, y: titlebarY))
            miniaturize.setFrameOrigin(NSPoint(x: close.frame.maxX + 8, y: titlebarY))
            zoom.setFrameOrigin(NSPoint(x: miniaturize.frame.maxX + 8, y: titlebarY))
            close.isHidden = false
            miniaturize.isHidden = false
            zoom.isHidden = false
            close.translatesAutoresizingMaskIntoConstraints = true
            miniaturize.translatesAutoresizingMaskIntoConstraints = true
            zoom.translatesAutoresizingMaskIntoConstraints = true
        }
    }
}
