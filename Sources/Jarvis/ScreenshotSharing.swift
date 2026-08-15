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

enum ClipboardSharing {
    static func itemProvider(for item: ClipboardItem) -> NSItemProvider? {
        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            let provider = NSItemProvider(object: NSString(string: text))
            provider.suggestedName = item.fileName
            return provider
        case .image:
            guard let path = item.imagePath,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path))
            else {
                return nil
            }
            return ScreenshotSharing.itemProvider(
                data: data,
                suggestedName: item.fileName ?? "图片.png"
            )
        case .file, .video:
            guard let path = item.filePath,
                  FileManager.default.fileExists(atPath: path)
            else {
                return nil
            }
            let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path))
            provider?.suggestedName = item.fileName
            return provider
        }
    }

    static func shareItems(for item: ClipboardItem) -> [Any]? {
        switch item.kind {
        case .text:
            guard let text = item.text else { return nil }
            return [NSString(string: text)]
        case .image:
            guard let path = item.imagePath,
                  let image = NSImage(contentsOfFile: path)
            else {
                return nil
            }
            return [image]
        case .file, .video:
            guard let path = item.filePath,
                  FileManager.default.fileExists(atPath: path)
            else {
                return nil
            }
            return [URL(fileURLWithPath: path) as NSURL]
        }
    }
}

/// Bridges the native macOS sharing picker into SwiftUI while keeping the
/// picker anchored to the button that opened it.
struct ScreenshotShareButton: NSViewRepresentable {
    private let items: [Any]
    let accessibilityLabel: String

    init(data: Data, accessibilityLabel: String) {
        self.items = NSImage(data: data).map { [$0] } ?? []
        self.accessibilityLabel = accessibilityLabel
    }

    init(items: [Any], accessibilityLabel: String) {
        self.items = items
        self.accessibilityLabel = accessibilityLabel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: items, accessibilityLabel: accessibilityLabel)
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
        context.coordinator.items = items
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
        var items: [Any]
        var accessibilityLabel: String
        private var sharingPicker: NSSharingServicePicker?

        init(items: [Any], accessibilityLabel: String) {
            self.items = items
            self.accessibilityLabel = accessibilityLabel
        }

        @objc func share(_ sender: NSButton) {
            guard !items.isEmpty else { return }
            sharingPicker = NSSharingServicePicker(items: items)
            sharingPicker?.show(
                relativeTo: sender.bounds,
                of: sender,
                preferredEdge: .minY
            )
        }
    }
}

struct ClipboardShareButton: View {
    let item: ClipboardItem

    var body: some View {
        if let items = ClipboardSharing.shareItems(for: item) {
            ScreenshotShareButton(
                items: items,
                accessibilityLabel: "分享剪贴板内容"
            )
        }
    }
}
