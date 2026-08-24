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
final class ScreenshotHistoryStore {
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
            .appendingPathComponent("Jarvis", isDirectory: true)
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
                .filter { fileManager.fileExists(atPath: directoryURL.appendingPathComponent($0.fileName).path) }
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            JarvisPersistenceLog.logger.error(
                "读取截图历史索引失败：\(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func data(for item: ScreenshotHistoryItem) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: item))
        } catch {
            JarvisPersistenceLog.logger.error(
                "读取历史截图失败：\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    func fileURL(for item: ScreenshotHistoryItem) -> URL {
        directoryURL.appendingPathComponent(item.fileName)
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
            try fileManager.removeItem(at: directoryURL.appendingPathComponent(item.fileName))
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
        do {
            try data.write(
                to: directoryURL.appendingPathComponent(item.fileName),
                options: .atomic
            )
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
                try fileManager.removeItem(at: directoryURL.appendingPathComponent(removed.fileName))
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
}
