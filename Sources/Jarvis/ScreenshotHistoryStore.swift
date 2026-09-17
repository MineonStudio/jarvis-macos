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
    /// 只按条数封顶挡不住体积：单张截图 1-20MB 不等，100 张 Retina 全屏可以到
    /// 1-2GB，而用户完全看不到占用。所以再加一道总字节上限。
    ///
    /// 刻意**不**按时间淘汰：那会在升级后静默删掉用户几个月前的截图，而体积问题
    /// 已经由字节上限解决了。
    private let maximumCount: Int
    private let maximumTotalBytes: Int64
    /// 孤儿回收每次运行只做一次（`load()` 在每次增删改后都会被调用）。
    private var hasCollectedOrphans = false

    init(
        fileManager: FileManager = .default,
        maximumCount: Int = 100,
        maximumTotalBytes: Int64 = 512 * 1024 * 1024
    ) {
        self.fileManager = fileManager
        self.maximumCount = maximumCount
        self.maximumTotalBytes = maximumTotalBytes
        let directory = JarvisAppDirectory.url("ScreenshotHistory", fileManager: fileManager)
        directoryURL = directory
        file = JarvisJSONFile(
            directoryURL: directory,
            fileName: "metadata.json",
            logDomain: "screenshot.history",
            fileManager: fileManager
        )
    }

    init(
        directoryURL: URL,
        fileManager: FileManager = .default,
        maximumCount: Int = 100,
        maximumTotalBytes: Int64 = 512 * 1024 * 1024
    ) {
        self.fileManager = fileManager
        self.maximumCount = maximumCount
        self.maximumTotalBytes = maximumTotalBytes
        self.directoryURL = directoryURL
        file = JarvisJSONFile(
            directoryURL: directoryURL,
            fileName: "metadata.json",
            logDomain: "screenshot.history",
            fileManager: fileManager
        )
    }

    func load() -> [ScreenshotHistoryItem] {
        lock.withLock {
            let items = loadLocked()
            collectOrphansIfNeeded(keeping: items)
            return items
        }
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
            guard save(trimmed(items)) else {
                // 索引没写成功，这张 PNG 永远进不了索引，也永远不会被淘汰——
                // 收回来，别留在磁盘上。
                discardFile(for: item)
                return nil
            }
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
        var kept: [ScreenshotHistoryItem] = []
        var totalBytes: Int64 = 0

        for item in sorted {
            let size = fileSize(of: item)
            let overCount = kept.count >= maximumCount
            // 第一张永远留着：单张就可能超过总上限，否则一张都存不下。
            let overBytes = !kept.isEmpty && totalBytes + size > maximumTotalBytes
            if overCount || overBytes {
                discardFile(for: item)
            } else {
                kept.append(item)
                totalBytes += size
            }
        }
        return kept
    }

    private func fileSize(of item: ScreenshotHistoryItem) -> Int64 {
        guard let url = safeFileURL(for: item.fileName),
              let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    private func discardFile(for item: ScreenshotHistoryItem) {
        guard let url = safeFileURL(for: item.fileName) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "screenshot.history.trim.failed",
                error: error
            )
        }
    }

    /// 删掉目录里没有被索引引用的 `screenshot-*.png`。
    ///
    /// 这些文件不会出现在历史里、也不会被淘汰（淘汰是按索引来的），只会一直占着
    /// 磁盘：索引写失败留下的、以及索引损坏被隔离后整批失去引用的。
    private func collectOrphansIfNeeded(keeping items: [ScreenshotHistoryItem]) {
        guard !hasCollectedOrphans else { return }
        hasCollectedOrphans = true

        let referenced = Set(items.map(\.fileName))
        let contents = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        var removedCount = 0
        for url in contents where url.pathExtension.lowercased() == "png" {
            let name = url.lastPathComponent
            guard name.hasPrefix("screenshot-"), !referenced.contains(name) else { continue }
            // 只认名字合法的：非法名字留给人工处理，别误删别人的东西。
            guard safeFileURL(for: name) != nil else { continue }
            try? fileManager.removeItem(at: url)
            removedCount += 1
        }
        guard removedCount > 0 else { return }
        JarvisLog.notice(
            category: .storage,
            event: "screenshot.history.orphansCollected",
            result: "success",
            fields: ["count": String(removedCount)]
        )
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
