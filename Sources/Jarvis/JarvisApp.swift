import AppKit
import SwiftUI

@main
struct JarvisApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup("Jarvis") {
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

        Settings {
            SettingsView()
                .environmentObject(appModel)
                .jarvisTheme(
                    appModel.themePreference,
                    systemColorScheme: appModel.systemColorScheme
                )
                .frame(width: 620, height: 520)
        }
    }
}

/// Makes the main window's native titlebar share the same visual plane as the
/// SwiftUI content while keeping the standard macOS window controls.
private struct JarvisMainWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = true
        window.backgroundColor = .textBackgroundColor

        // Keep the native titlebar's backing layers on the same semantic
        // color as the SwiftUI page. This avoids the titlebar material being
        // composited as a visibly lighter strip above the content.
        let backgroundColor = NSColor.textBackgroundColor.cgColor
        for view in [window.contentView, window.contentView?.superview].compactMap({ $0 }) {
            view.wantsLayer = true
            view.layer?.backgroundColor = backgroundColor
        }

        if let close = window.standardWindowButton(.closeButton),
           let miniaturize = window.standardWindowButton(.miniaturizeButton),
           let zoom = window.standardWindowButton(.zoomButton) {
            var titlebarAncestor = close.superview
            while let view = titlebarAncestor {
                view.wantsLayer = true
                view.layer?.backgroundColor = backgroundColor
                titlebarAncestor = view.superview
            }

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
