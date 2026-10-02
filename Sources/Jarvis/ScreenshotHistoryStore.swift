import Foundation

struct ScreenshotHistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let fileName: String

    /// 拖到别处（Finder、聊天窗口）时落盘用的名字。
    ///
    /// `fileName` 是内部名（`screenshot-<uuid>.png`，索引照它找文件），用户不该看见
    /// 一串 UUID。时间取 `updatedAt`：界面里显示的是它，文件内容也是那一次写进去的
    /// （改过再存的截图，`createdAt` 会是更早的时刻）。
    var suggestedFileName: String {
        ScreenshotFileName.timestamped(at: updatedAt)
    }
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
    /// 孤儿回收每次运行只做一次（`load()` 在每次增删改后都会被调用）。
    private var hasCollectedOrphans = false

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

    init(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) {
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
            guard save(items) else {
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
            // #7：先写同目录临时文件，索引落盘成功后再原子替换原图。
            // 索引失败时原图纹丝不动，不会出现"内容已变、元数据没变"的分叉。
            guard let tempURL = writeTemp(data, for: item) else { return nil }

            var updated = items[index]
            updated.updatedAt = date
            items[index] = updated
            guard save(items) else {
                try? fileManager.removeItem(at: tempURL)
                return nil
            }
            guard replaceFile(for: item, with: tempURL) else { return nil }
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

    func fileSize(ofStored item: ScreenshotHistoryItem) -> Int64? {
        lock.withLock {
            let size = fileSize(of: item)
            return size > 0 ? size : nil
        }
    }

    func storedUsage() -> (bytes: Int64, fileCount: Int) {
        lock.withLock {
            let urls = (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            var bytes: Int64 = 0
            var fileCount = 0
            for url in urls where url.pathExtension.lowercased() == "png" {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                bytes += size
                fileCount += 1
            }
            return (bytes, fileCount)
        }
    }

    @discardableResult
    func delete(olderThan cutoff: Date) -> Int {
        lock.withLock {
            let stale = loadLocked().filter { $0.updatedAt < cutoff }
            guard !stale.isEmpty else { return 0 }
            for item in stale {
                discardFile(for: item)
            }
            let staleIDs = Set(stale.map(\.id))
            let remaining = loadLocked().filter { !staleIDs.contains($0.id) }
            guard save(remaining) else { return 0 }
            return stale.count
        }
    }

    private func fileSize(of item: ScreenshotHistoryItem) -> Int64 {
        guard let url = safeFileURL(for: item.fileName),
              let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    /// #7 的两个帮手：临时文件以 "." 开头，storedUsage 统计时自动跳过。
    private func writeTemp(_ data: Data, for item: ScreenshotHistoryItem) -> URL? {
        guard let url = safeFileURL(for: item.fileName) else { return nil }
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(item.fileName).tmp-\(UUID().uuidString)")
        do {
            try JarvisProtectedStorage.write(data, to: tempURL)
            return tempURL
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "screenshot.history.writeTemp.failed",
                error: error
            )
            return nil
        }
    }

    private func replaceFile(for item: ScreenshotHistoryItem, with tempURL: URL) -> Bool {
        guard let url = safeFileURL(for: item.fileName) else {
            try? fileManager.removeItem(at: tempURL)
            return false
        }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.replaceItem(
                    at: url,
                    withItemAt: tempURL,
                    backupItemName: nil,
                    options: [],
                    resultingItemURL: nil
                )
            } else {
                // 原图已被外部删掉：直接搬过去，索引与内容依然一致。
                try fileManager.moveItem(at: tempURL, to: url)
            }
            return true
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "screenshot.history.replace.failed",
                error: error
            )
            try? fileManager.removeItem(at: tempURL)
            return false
        }
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
