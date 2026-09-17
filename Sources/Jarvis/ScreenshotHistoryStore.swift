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
            // 先算淘汰、**先写索引**，成功之后才删文件：反过来的话，索引写失败时
            // 磁盘上的索引仍引用着已经被删掉的图，界面上那些条目还在，点开却报
            // 「历史截图文件不存在」，而且每 add 一次就多删一批。
            let (kept, removed) = trimmed(items)
            guard save(kept) else {
                discardFile(for: item)
                return nil
            }
            for stale in removed {
                discardFile(for: stale)
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
            // 重新编辑会让某张图变大，所以这里同样要过一遍容量约束。
            let (kept, removed) = trimmed(items)
            guard save(kept) else { return nil }
            for stale in removed {
                discardFile(for: stale)
            }
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

    /// 按「条数 + 总字节」算出该留哪些、该淘汰哪些。**不删文件**——删要等索引
    /// 写成功之后由调用方做，否则一次失败的写入会连带删掉索引里还引用着的图。
    private func trimmed(
        _ items: [ScreenshotHistoryItem]
    ) -> (kept: [ScreenshotHistoryItem], removed: [ScreenshotHistoryItem]) {
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        var kept: [ScreenshotHistoryItem] = []
        var removed: [ScreenshotHistoryItem] = []
        var totalBytes: Int64 = 0

        for item in sorted {
            let size = fileSize(of: item)
            let overCount = kept.count >= maximumCount
            // 第一张永远留着：单张就可能超过总上限，否则一张都存不下。
            let overBytes = !kept.isEmpty && totalBytes + size > maximumTotalBytes
            if overCount || overBytes {
                removed.append(item)
            } else {
                kept.append(item)
                totalBytes += size
            }
        }
        if !removed.isEmpty {
            // 淘汰是「最旧的先走」。用户看不到这个仓库的占用，所以至少让日志说得清。
            JarvisLog.notice(
                category: .storage,
                event: "screenshot.history.trimmed",
                result: "success",
                fields: [
                    "removed": String(removed.count),
                    "kept": String(kept.count),
                    "keptBytes": String(totalBytes)
                ]
            )
        }
        return (kept, removed)
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
    /// 磁盘。但「没被引用」有几种成因，其中一种是**索引读不出来**——那时删文件
    /// 等于把用户的历史销毁掉，所以下面几道门禁一个都不能省。
    private func collectOrphansIfNeeded(keeping items: [ScreenshotHistoryItem]) {
        guard !hasCollectedOrphans else { return }
        hasCollectedOrphans = true

        let contents = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        // ① 索引被隔离过（`.corrupt-*` 还在）说明这次读到的是坏索引，`items` 是空的
        //    并不代表磁盘上的图没人要。这种时候一张都不许删。
        guard !contents.contains(where: { $0.lastPathComponent.contains(".corrupt-") }) else {
            JarvisLog.notice(
                category: .storage,
                event: "screenshot.history.orphanSweepSkipped",
                result: "skipped",
                fields: ["reason": "quarantinedIndex"]
            )
            return
        }

        let referenced = Set(items.map(\.fileName))
        // ② 刚写出来、索引还没来得及落盘的图不能被当成孤儿。索引写在另一个队列上，
        //    别的 Store 实例（启动仓库）也扫同一个目录。
        let gracePeriod: TimeInterval = 10 * 60
        let cutoff = Date().addingTimeInterval(-gracePeriod)
        var removedCount = 0
        var failedCount = 0
        for url in contents where url.pathExtension.lowercased() == "png" {
            let name = url.lastPathComponent
            guard name.hasPrefix("screenshot-"), !referenced.contains(name) else { continue }
            // 只认名字合法的：非法名字留给人工处理，别误删别人的东西。
            guard safeFileURL(for: name) != nil else { continue }
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, modified > cutoff
            {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
                removedCount += 1
            } catch CocoaError.fileNoSuchFile {
                continue
            } catch {
                failedCount += 1
                JarvisLog.error(
                    category: .storage,
                    event: "screenshot.history.orphanRemoval.failed",
                    error: error
                )
            }
        }
        guard removedCount > 0 || failedCount > 0 else { return }
        JarvisLog.notice(
            category: .storage,
            event: "screenshot.history.orphansCollected",
            result: failedCount == 0 ? "success" : "partial",
            fields: ["count": String(removedCount), "failed": String(failedCount)]
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
