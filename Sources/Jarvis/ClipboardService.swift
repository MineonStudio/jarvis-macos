import AppKit
import AVFoundation
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardLimits {
    static let maximumItemCount = 300
    static let maximumStoredFileSize: Int64 = 1024 * 1024 * 1024
}

enum ClipboardKind: String, Codable, CaseIterable {
    case text
    case image
    case file
    case video

    var title: String {
        switch self {
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        case .video: "视频"
        }
    }

    var icon: String {
        switch self {
        case .text: "doc.text"
        case .image: "photo"
        case .file: "doc"
        case .video: "video"
        }
    }
}

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let kind: ClipboardKind
    let text: String?
    let imagePath: String?
    let filePath: String?
    let thumbnailPath: String?
    let fileName: String?
    let fileSize: Int64?
    let fileUTI: String?
    let fingerprintValue: String?
    let isStoredCopy: Bool
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ClipboardKind,
        text: String? = nil,
        imagePath: String? = nil,
        filePath: String? = nil,
        thumbnailPath: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        fileUTI: String? = nil,
        fingerprintValue: String? = nil,
        isStoredCopy: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileUTI = fileUTI
        self.fingerprintValue = fingerprintValue
        self.isStoredCopy = isStoredCopy
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, text, imagePath, filePath, thumbnailPath, fileName
        case fileSize, fileUTI, fingerprintValue, isStoredCopy, isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decode(ClipboardKind.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        fileUTI = try container.decodeIfPresent(String.self, forKey: .fileUTI)
        fingerprintValue = try container.decodeIfPresent(String.self, forKey: .fingerprintValue)
        isStoredCopy = try container.decodeIfPresent(Bool.self, forKey: .isStoredCopy)
            ?? (kind == .image && imagePath?.contains("/Jarvis/Clipboard/") == true)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var fingerprint: String {
        if let fingerprintValue {
            return "\(kind.rawValue):\(fingerprintValue)"
        }
        if let text {
            return "text:\(text)"
        }
        if let imagePath {
            return "image:\(imagePath)"
        }
        if let filePath {
            return "\(kind.rawValue):\(filePath)"
        }
        return id.uuidString
    }

    var preview: String {
        switch kind {
        case .text:
            text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? text ?? "文本"
                : "空文本"
        case .image:
            "图片"
        case .file, .video:
            fileName ?? URL(fileURLWithPath: filePath ?? "").lastPathComponent
        }
    }

    var hasLocalContent: Bool {
        switch kind {
        case .text:
            return text != nil
        case .image:
            guard let imagePath else { return false }
            return FileManager.default.fileExists(atPath: imagePath)
        case .file, .video:
            guard let filePath else { return false }
            return FileManager.default.fileExists(atPath: filePath)
        }
    }

    var sizeDescription: String? {
        guard let fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: fileSize)
    }

    var shortTimestamp: String {
        createdAt.formatted(.dateTime.year().month().day().hour().minute())
    }
}

final class ClipboardService {
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var onChange: ((ClipboardItem) -> Void)?

    func start(onChange: @escaping (ClipboardItem) -> Void) {
        self.onChange = onChange
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func markCurrentPasteboardAsHandled() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        timer?.invalidate()
    }

    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let fingerprint = digest(Data(text.utf8))
            onChange?(ClipboardItem(
                kind: .text,
                text: text,
                fingerprintValue: fingerprint
            ))
            return
        }

        if let imageData = imageData(from: pasteboard),
           let path = saveData(imageData, fileExtension: "png")
        {
            onChange?(ClipboardItem(
                kind: .image,
                imagePath: path,
                fileName: "图片.png",
                fileSize: Int64(imageData.count),
                fileUTI: UTType.png.identifier,
                fingerprintValue: digest(imageData),
                isStoredCopy: true
            ))
            return
        }

        guard let url = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )?.compactMap({ $0 as? URL }).first,
            url.isFileURL else { return }

        captureFile(url)
    }

    private func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        guard let tiffData = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func captureFile(_ url: URL) {
        let callback = onChange
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .contentModificationDateKey])
            else {
                return
            }

            let fileSize = Int64(values.fileSize ?? 0)
            let contentType = values.contentType
            let kind = Self.kind(for: url, contentType: contentType)
            let storedPath = storeFile(url, fileSize: fileSize)
            let path = storedPath ?? url.path
            let finishCapture: (String?) -> Void = { thumbnailPath in
                let fingerprint = "\(url.path)|\(fileSize)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                let item = ClipboardItem(
                    kind: kind,
                    filePath: path,
                    thumbnailPath: thumbnailPath,
                    fileName: url.lastPathComponent,
                    fileSize: fileSize,
                    fileUTI: contentType?.identifier,
                    fingerprintValue: fingerprint,
                    isStoredCopy: storedPath != nil
                )
                DispatchQueue.main.async {
                    callback?(item)
                }
            }

            guard kind == .video else {
                finishCapture(nil)
                return
            }

            ClipboardVideoThumbnailGenerator.makeCGImageAsync(for: URL(fileURLWithPath: path)) { [weak self] image in
                guard let self,
                      let image,
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else {
                    finishCapture(nil)
                    return
                }
                finishCapture(self.saveData(data, fileExtension: "png"))
            }
        }
    }

    private static func kind(for url: URL, contentType: UTType?) -> ClipboardKind {
        if contentType?.conforms(to: .movie) == true {
            return .video
        }
        let videoExtensions = Set(["mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv"])
        return videoExtensions.contains(url.pathExtension.lowercased()) ? .video : .file
    }

    private func storeFile(_ sourceURL: URL, fileSize: Int64) -> String? {
        // Keep very large files as references so copying a movie never blocks
        // the app or silently fills the user's disk.
        guard fileSize <= ClipboardLimits.maximumStoredFileSize else { return nil }
        do {
            let directory = try storageDirectory()
            let extensionPart = sourceURL.pathExtension.isEmpty ? "" : ".\(sourceURL.pathExtension)"
            let destination = directory.appendingPathComponent("file-\(UUID().uuidString)\(extensionPart)")
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    private func saveData(_ data: Data, fileExtension: String) -> String? {
        do {
            let directory = try storageDirectory()
            let path = directory.appendingPathComponent("item-\(UUID().uuidString).\(fileExtension)")
            try data.write(to: path, options: .atomic)
            return path.path
        } catch {
            return nil
        }
    }

    private func storageDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Jarvis/Clipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

final class ClipboardStore {
    private let fileURL: URL

    init() {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("Jarvis", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("clipboard-history.json")
    }

    func load() -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try sort(JSONDecoder().decode([ClipboardItem].self, from: data))
        } catch {
            JarvisPersistenceLog.logger.error(
                "读取剪贴板历史失败：\(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    @discardableResult
    func save(_ items: [ClipboardItem]) -> Bool {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            JarvisPersistenceLog.logger.error(
                "写入剪贴板历史失败：\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func removeStoredFiles(for items: [ClipboardItem]) {
        for item in items {
            if let thumbnailPath = item.thumbnailPath {
                removeStoredFile(atPath: thumbnailPath)
            }

            let path: String? = switch item.kind {
            case .image: item.imagePath
            case .file, .video: item.filePath
            case .text: nil
            }
            guard item.isStoredCopy, let path else { continue }
            removeStoredFile(atPath: path)
        }
    }

    private func removeStoredFile(atPath path: String) {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            JarvisPersistenceLog.logger.error(
                "删除剪贴板本地文件失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func sort(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned
            }
            return $0.createdAt > $1.createdAt
        }
    }
}
