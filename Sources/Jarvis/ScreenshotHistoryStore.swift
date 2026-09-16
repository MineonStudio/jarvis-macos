import Foundation

struct ScreenshotHistoryItem: Codable, Identifiable, Equatable, Sendable {
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
    private let file: JarvisJSONFile<[ScreenshotHistoryItem]>
    /// 只保护「写 PNG + 改索引」这类组合操作；单次文件读写的锁在 `file` 里。
    private let lock = NSLock()
    private let maximumCount = 100

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let directory = JarvisAppDirectory.url("ScreenshotHistory", fileManager: fileManager)
        directoryURL = directory
        file = JarvisJSONFile(
            directoryURL: directory,
            fileName: "metadata.json",
            logDomain: "screenshot.history",
            fileManager: fileManager
        )
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
        file = JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "metadata.json",
            logDomain: "screenshot.history",
            fileManager: fileManager
        )
    }

    func load() -> [ScreenshotHistoryItem] {
        lock.withLock { loadLocked() }
    }

    private func loadLocked() -> [ScreenshotHistoryItem] {
        usable(file.readOrDefault([]))
    }

    /// 写入所依据的索引。索引读不出来又留不下证据时拒绝继续，否则整份历史会被一个
    /// 空数组覆盖掉。
    private func itemsForWriting() throws -> [ScreenshotHistoryItem] {
        try usable(file.readForWriting(default: []))
    }

    private func usable(_ items: [ScreenshotHistoryItem]) -> [ScreenshotHistoryItem] {
        items
            .filter { item in
                guard let url = safeFileURL(for: item.fileName) else { return false }
                return fileManager.fileExists(atPath: url.path)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func data(for item: ScreenshotHistoryItem) -> Data? {
        lock.withLock {
            guard let url = safeFileURL(for: item.fileName) else {
                JarvisLog.error(
                    category: .security,
                    event: "screenshot.history.pathRejected",
                    fields: ["operation": "read"]
                )
                return nil
            }
            do {
                return try Data(contentsOf: url)
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.history.read.failed",
                    error: error
                )
                return nil
            }
        }
    }

    func fileURL(for item: ScreenshotHistoryItem) -> URL {
        safeFileURL(for: item.fileName)
            ?? directoryURL.appendingPathComponent(".invalid-history-file", isDirectory: false)
    }

    @discardableResult
    func add(data: Data, date: Date = Date()) -> ScreenshotHistoryItem? {
        guard !data.isEmpty else { return nil }
        return lock.withLock {
            let id = UUID()
            let item = ScreenshotHistoryItem(
                id: id,
                createdAt: date,
                updatedAt: date,
                fileName: "screenshot-\(id.uuidString).png"
            )
            guard write(data, for: item) else { return nil }

            guard var items = try? itemsForWriting() else {
                // 索引写不进去，那张 PNG 就永远进不了索引，收回来而不是留在磁盘上。
                if let url = safeFileURL(for: item.fileName) {
                    try? fileManager.removeItem(at: url)
                }
                return nil
            }
            items.removeAll { $0.id == item.id }
            items.insert(item, at: 0)
            guard save(trimmed(items)) else { return nil }
            return item
        }
    }

    @discardableResult
    func update(_ item: ScreenshotHistoryItem, data: Data, date: Date = Date()) -> ScreenshotHistoryItem? {
        guard !data.isEmpty else { return nil }
        return lock.withLock {
            guard var items = try? itemsForWriting() else { return nil }
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
            guard write(data, for: item) else { return nil }

            var updated = items[index]
            updated.updatedAt = date
            items[index] = updated
            guard save(items.sorted { $0.updatedAt > $1.updatedAt }) else { return nil }
            return updated
        }
    }

    @discardableResult
    func delete(_ item: ScreenshotHistoryItem) -> Bool {
        lock.withLock {
            do {
                guard let url = safeFileURL(for: item.fileName) else {
                    JarvisLog.error(
                        category: .security,
                        event: "screenshot.history.pathRejected",
                        fields: ["operation": "delete"]
                    )
                    return false
                }
                try fileManager.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // The metadata index still needs to be cleaned when the PNG was
                // already removed by an earlier failed cleanup.
            } catch {
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.history.delete.failed",
                    error: error
                )
                return false
            }
            guard var items = try? itemsForWriting() else { return false }
            items.removeAll { $0.id == item.id }
            return save(items)
        }
    }

    private func write(_ data: Data, for item: ScreenshotHistoryItem) -> Bool {
        guard let url = safeFileURL(for: item.fileName) else {
            JarvisLog.error(
                category: .security,
                event: "screenshot.history.pathRejected",
                fields: ["operation": "write"]
            )
            return false
        }
        do {
            try JarvisProtectedStorage.write(data, to: url)
            return true
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "screenshot.history.write.failed",
                error: error
            )
            return false
        }
    }

    @discardableResult
    private func save(_ items: [ScreenshotHistoryItem]) -> Bool {
        file.write(items)
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
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.history.trim.failed",
                    error: error
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
