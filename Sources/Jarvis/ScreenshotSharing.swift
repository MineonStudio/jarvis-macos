import AppKit
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
}
