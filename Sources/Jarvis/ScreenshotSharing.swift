import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ScreenshotSharing {
    static func itemProvider(data: Data, suggestedName: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = suggestedName.hasSuffix(".png")
            ? suggestedName
            : "\(suggestedName).png"

        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }

        // Finder and some desktop applications prefer a file representation
        // when the drag destination is a folder. Keep the data representation
        // above as the fallback for Mail, WeChat, editors and other image
        // consumers that request the PNG bytes directly.
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Jarvis-\(UUID().uuidString).png")
            do {
                try data.write(to: fileURL, options: .atomic)
                completion(fileURL, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return Progress()
        }

        return provider
    }
}

/// Bridges the native macOS sharing picker into SwiftUI while keeping the
/// picker anchored to the button that opened it.
struct ScreenshotShareButton: NSViewRepresentable {
    let data: Data
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(data: data, accessibilityLabel: accessibilityLabel)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.data = data
        context.coordinator.accessibilityLabel = accessibilityLabel
        update(nsView, coordinator: context.coordinator)
    }

    private func update(_ button: NSButton, coordinator: Coordinator) {
        button.image = NSImage(
            systemSymbolName: "square.and.arrow.up",
            accessibilityDescription: coordinator.accessibilityLabel
        )
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(coordinator.accessibilityLabel)
        button.toolTip = coordinator.accessibilityLabel
    }

    final class Coordinator: NSObject {
        var data: Data
        var accessibilityLabel: String
        private var sharingPicker: NSSharingServicePicker?

        init(data: Data, accessibilityLabel: String) {
            self.data = data
            self.accessibilityLabel = accessibilityLabel
        }

        @objc func share(_ sender: NSButton) {
            guard let image = NSImage(data: data) else { return }
            sharingPicker = NSSharingServicePicker(items: [image])
            sharingPicker?.show(
                relativeTo: sender.bounds,
                of: sender,
                preferredEdge: .minY
            )
        }
    }
}
