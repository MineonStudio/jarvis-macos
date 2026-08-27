import Foundation

struct ScreenshotHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let fileName: String
}

/// Stores screenshot history as PNG files plus a small JSON index. Keeping the
/// image data out of UserDefaults makes history durable without making the
/// app's preferences file grow with every screenshot.
final class ScreenshotHistoryStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let metadataURL: URL
    private let maximumCount = 100

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let supportDirectory = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = supportDirectory
            .appendingPathComponent(JarvisAppIdentity.dataDirectoryName, isDirectory: true)
            .appendingPathComponent("ScreenshotHistory", isDirectory: true)
        directoryURL = directory
        metadataURL = directory.appendingPathComponent("metadata.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        metadataURL = directoryURL.appendingPathComponent("metadata.json")
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func load() -> [ScreenshotHistoryItem] {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            let items = try JSONDecoder().decode([ScreenshotHistoryItem].self, from: data)
            return items
                .filter { item in
                    guard let url = safeFileURL(for: item.fileName) else { return false }
                    return fileManager.fileExists(atPath: url.path)
                }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            JarvisPersistenceLog.logger.error(
                "读取截图历史索引失败：\(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func data(for item: ScreenshotHistoryItem) -> Data? {
        guard let url = safeFileURL(for: item.fileName) else {
            JarvisPersistenceLog.logger.error("拒绝读取越界的截图历史路径")
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            JarvisPersistenceLog.logger.error(
                "读取历史截图失败：\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func fileURL(for item: ScreenshotHistoryItem) -> URL {
        safeFileURL(for: item.fileName)
            ?? directoryURL.appendingPathComponent(".invalid-history-file", isDirectory: false)
    }

    func fileSize(for item: ScreenshotHistoryItem) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL(for: item).path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return nil
        }
        return fileSize.int64Value
    }

    @discardableResult
    func add(data: Data, date: Date = Date()) -> ScreenshotHistoryItem? {
        guard !data.isEmpty else { return nil }
        let id = UUID()
        let item = ScreenshotHistoryItem(
            id: id,
            createdAt: date,
            updatedAt: date,
            fileName: "screenshot-\(id.uuidString).png"
        )
        guard write(data, for: item) else { return nil }

        var items = load()
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        guard save(trimmed(items)) else { return nil }
        return item
    }

    @discardableResult
    func update(_ item: ScreenshotHistoryItem, data: Data, date: Date = Date()) -> ScreenshotHistoryItem? {
        guard !data.isEmpty else { return nil }
        var items = load()
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        guard write(data, for: item) else { return nil }

        var updated = items[index]
        updated.updatedAt = date
        items[index] = updated
        guard save(items.sorted { $0.updatedAt > $1.updatedAt }) else { return nil }
        return updated
    }

    @discardableResult
    func delete(_ item: ScreenshotHistoryItem) -> Bool {
        do {
            guard let url = safeFileURL(for: item.fileName) else {
                JarvisPersistenceLog.logger.error("拒绝删除越界的截图历史路径")
                return false
            }
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // The metadata index still needs to be cleaned when the PNG was
            // already removed by an earlier failed cleanup.
        } catch {
            JarvisPersistenceLog.logger.error(
                "删除历史截图文件失败：\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
        var items = load()
        items.removeAll { $0.id == item.id }
        return save(items)
    }

    private func write(_ data: Data, for item: ScreenshotHistoryItem) -> Bool {
        guard let url = safeFileURL(for: item.fileName) else {
            JarvisPersistenceLog.logger.error("拒绝写入越界的截图历史路径")
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            JarvisPersistenceLog.logger.error(
                "写入历史截图失败：\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    private func save(_ items: [ScreenshotHistoryItem]) -> Bool {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: metadataURL, options: .atomic)
            return true
        } catch {
            JarvisPersistenceLog.logger.error(
                "写入截图历史索引失败：\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private func trimmed(_ items: [ScreenshotHistoryItem]) -> [ScreenshotHistoryItem] {
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        guard sorted.count > maximumCount else { return sorted }

        let kept = Array(sorted.prefix(maximumCount))
        let keptIDs = Set(kept.map(\.id))
        for removed in sorted where !keptIDs.contains(removed.id) {
            do {
                guard let url = safeFileURL(for: removed.fileName) else { continue }
                try fileManager.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                continue
            } catch {
                JarvisPersistenceLog.logger.error(
                    "清理超量历史截图失败：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return kept
    }

    private func safeFileURL(for fileName: String) -> URL? {
        let prefix = "screenshot-"
        let suffix = ".png"
        guard fileName.hasPrefix(prefix), fileName.hasSuffix(suffix) else { return nil }
        let uuidString = String(fileName.dropFirst(prefix.count).dropLast(suffix.count))
        guard UUID(uuidString: uuidString) != nil else { return nil }

        let url = directoryURL.appendingPathComponent(fileName, isDirectory: false)
        guard url.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL else {
            return nil
        }
        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true
        {
            return nil
        }
        return url
    }
}
