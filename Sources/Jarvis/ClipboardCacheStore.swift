import Foundation

enum ClipboardCacheCategory: String, CaseIterable, Identifiable {
    case all
    case favorites
    case text
    case image
    case file
    case video

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .favorites: "收藏"
        case .text: "文本"
        case .image: "图片"
        case .file: "文件"
        case .video: "视频"
        }
    }

    var icon: String? {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star.fill"
        case .text: ClipboardKind.text.icon
        case .image: ClipboardKind.image.icon
        case .file: ClipboardKind.file.icon
        case .video: ClipboardKind.video.icon
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: true
        case .favorites: item.isPinned
        case .text: item.kind == .text
        case .image: item.kind == .image
        case .file: item.kind == .file
        case .video: item.kind == .video
        }
    }
}

enum ClipboardCacheCleanupPeriod: String, CaseIterable, Identifiable {
    case threeDays
    case sevenDays
    case oneMonth
    case halfYear

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .threeDays: "超过 3 天"
        case .sevenDays: "超过 7 天"
        case .oneMonth: "超过 1 个月"
        case .halfYear: "超过半年"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .threeDays: 3 * 24 * 60 * 60
        case .sevenDays: 7 * 24 * 60 * 60
        case .oneMonth: 30 * 24 * 60 * 60
        case .halfYear: 182 * 24 * 60 * 60
        }
    }

    var cutoffDate: Date {
        Date().addingTimeInterval(-interval)
    }
}

struct ClipboardCacheUsage: Equatable {
    let usedBytes: Int64
    let capacityBytes: Int64
    let fileCount: Int

    var fraction: Double {
        guard capacityBytes > 0 else { return 1 }
        guard usedBytes < capacityBytes else { return 1 }
        return max(Double(usedBytes) / Double(capacityBytes), 0)
    }

    var isOverCapacity: Bool {
        usedBytes > capacityBytes
    }
}

struct ClipboardCacheMigration {
    let items: [ClipboardItem]
    let legacyPaths: [String]
}

final class ClipboardCacheStore: @unchecked Sendable {
    static let defaultMaximumBytes: Int64 = 5 * 1024 * 1024 * 1024
    static let minimumMaximumBytes: Int64 = 256 * 1024 * 1024
    static let maximumMaximumBytes: Int64 = 10 * 1024 * 1024 * 1024
    static let supportedMaximumBytes: [Int64] = [minimumMaximumBytes]
        + (1 ... 10).map { Int64($0) * 1024 * 1024 * 1024 }

    private static let directoryKey = "jarvis.clipboard.cache.directory"
    private static let maximumBytesKey = "jarvis.clipboard.cache.maximum-bytes"

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var directoryURL: URL
    private var maximumBytes: Int64

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.defaults = defaults

        let defaultDirectory = Self.defaultDirectory(fileManager: fileManager)
        let storedDirectory = defaults.string(forKey: Self.directoryKey)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        directoryURL = storedDirectory ?? defaultDirectory

        let storedMaximum = defaults.object(forKey: Self.maximumBytesKey) as? NSNumber
        maximumBytes = Self.normalizedMaximumBytes(storedMaximum?.int64Value ?? Self.defaultMaximumBytes)

        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    var currentDirectoryURL: URL {
        lock.withLock { directoryURL }
    }

    var currentMaximumBytes: Int64 {
        lock.withLock { maximumBytes }
    }

    func updateMaximumBytes(_ value: Int64) {
        let clamped = Self.normalizedMaximumBytes(value)
        lock.withLock {
            maximumBytes = clamped
            defaults.set(clamped, forKey: Self.maximumBytesKey)
        }
    }

    func usage() -> ClipboardCacheUsage {
        lock.withLock { usageLocked() }
    }

    func storeFile(_ sourceURL: URL, fileSize _: Int64) -> String? {
        lock.withLock {
            guard
                let values = try? sourceURL.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                ),
                values.isRegularFile == true,
                let sourceSize = values.fileSize,
                sourceSize >= 0,
                Int64(sourceSize) <= maximumBytes,
                usageLocked().usedBytes + Int64(sourceSize) <= maximumBytes,
                let destination = makeDestinationLocked(extension: sourceURL.pathExtension)
            else {
                return nil
            }

            do {
                try fileManager.copyItem(at: sourceURL, to: destination)
                return destination.path
            } catch {
                JarvisPersistenceLog.logger.error(
                    "复制剪贴板文件失败：\(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    func storeData(_ data: Data, fileExtension: String) -> String? {
        lock.withLock {
            let dataSize = Int64(data.count)
            guard
                dataSize <= maximumBytes,
                usageLocked().usedBytes + dataSize <= maximumBytes,
                let destination = makeDestinationLocked(extension: fileExtension)
            else {
                return nil
            }

            do {
                try data.write(to: destination, options: .atomic)
                return destination.path
            } catch {
                JarvisPersistenceLog.logger.error(
                    "写入剪贴板缓存失败：\(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    func removeStoredFile(atPath path: String) {
        do {
            try fileManager.removeItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            JarvisPersistenceLog.logger.error(
                "删除剪贴板缓存失败：\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func removeLegacyFiles(atPaths paths: [String]) {
        for path in paths {
            removeStoredFile(atPath: path)
        }
    }

    /// Removes only files owned by the configured cache directory.
    /// External source files referenced by clipboard history are never touched.
    @discardableResult
    func removeManagedFiles(for items: [ClipboardItem]) -> Bool {
        lock.withLock {
            var succeeded = true
            for item in items {
                for url in managedFileURLsLocked(for: item) {
                    guard fileManager.fileExists(atPath: url.path) else { continue }
                    do {
                        try fileManager.removeItem(at: url)
                    } catch {
                        succeeded = false
                        JarvisPersistenceLog.logger.error(
                            "删除剪贴板缓存失败：\(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
            return succeeded
                && items.allSatisfy { managedFileURLsLocked(for: $0).allSatisfy { !fileManager.fileExists(atPath: $0.path) } }
        }
    }

    func hasManagedFiles(for item: ClipboardItem) -> Bool {
        lock.withLock {
            managedFileURLsLocked(for: item).contains { fileManager.fileExists(atPath: $0.path) }
        }
    }

    @discardableResult
    func removeOrphanedManagedFiles(
        referencedPaths: Set<String>,
        olderThan: Date? = nil
    ) -> Bool {
        lock.withLock {
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return false
            }

            let referenced = Set(referencedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
            var removed = false
            for case let url as URL in enumerator {
                let standardizedURL = url.standardizedFileURL
                guard
                    Self.isManagedFilename(standardizedURL.lastPathComponent),
                    !referenced.contains(standardizedURL.path),
                    let values = try? standardizedURL.resourceValues(
                        forKeys: [.isRegularFileKey, .contentModificationDateKey]
                    ),
                    values.isRegularFile == true,
                    (olderThan.map { (values.contentModificationDate ?? .distantFuture) < $0 } ?? true)
                else {
                    continue
                }

                do {
                    try fileManager.removeItem(at: standardizedURL)
                    removed = true
                } catch {
                    JarvisPersistenceLog.logger.error(
                        "删除孤立剪贴板缓存失败：\(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            return removed
        }
    }

    private func managedFileURLsLocked(for item: ClipboardItem) -> [URL] {
        let paths = item.cachePaths
        let rootPath = directoryURL.standardizedFileURL.path + "/"
        return paths.compactMap { (path: String) -> URL? in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.path.hasPrefix(rootPath) else { return nil }
            guard item.isStoredCopy || Self.isManagedFilename(url.lastPathComponent) else {
                return nil
            }
            return url
        }.reduce(into: [URL]()) { (result: inout [URL], url: URL) in
            if !result.contains(url) {
                result.append(url)
            }
        }
    }

    private static func isManagedFilename(_ filename: String) -> Bool {
        filename.hasPrefix("item-") || filename.hasPrefix("migrated-")
    }

    func migrateManagedFiles(
        for items: [ClipboardItem],
        to newDirectoryURL: URL
    ) throws -> ClipboardCacheMigration {
        try lock.withLock {
            let oldDirectoryURL = directoryURL.standardizedFileURL
            let destinationDirectoryURL = newDirectoryURL.standardizedFileURL
            guard oldDirectoryURL != destinationDirectoryURL else {
                return ClipboardCacheMigration(items: items, legacyPaths: [])
            }

            try fileManager.createDirectory(
                at: destinationDirectoryURL,
                withIntermediateDirectories: true
            )

            var migratedItems = items
            var copiedPaths: [String] = []
            var oldPaths: [String] = []

            do {
                for index in migratedItems.indices {
                    var item = migratedItems[index]
                    if let textPath = item.textPath,
                       let migration = try copyManagedFile(
                           textPath,
                           from: oldDirectoryURL,
                           to: destinationDirectoryURL
                       )
                    {
                        item.textPath = migration.path
                        if migration.didCopy {
                            copiedPaths.append(migration.path)
                        }
                        oldPaths.append(textPath)
                    }
                    if let imagePath = item.imagePath,
                       let migration = try copyManagedFile(
                           imagePath,
                           from: oldDirectoryURL,
                           to: destinationDirectoryURL
                       )
                    {
                        item.imagePath = migration.path
                        if migration.didCopy {
                            copiedPaths.append(migration.path)
                        }
                        oldPaths.append(imagePath)
                    }
                    if let filePath = item.filePath,
                       let migration = try copyManagedFile(
                           filePath,
                           from: oldDirectoryURL,
                           to: destinationDirectoryURL
                       )
                    {
                        item.filePath = migration.path
                        if migration.didCopy {
                            copiedPaths.append(migration.path)
                        }
                        oldPaths.append(filePath)
                    }
                    if let thumbnailPath = item.thumbnailPath,
                       let migration = try copyManagedFile(
                           thumbnailPath,
                           from: oldDirectoryURL,
                           to: destinationDirectoryURL
                       )
                    {
                        item.thumbnailPath = migration.path
                        if migration.didCopy {
                            copiedPaths.append(migration.path)
                        }
                        oldPaths.append(thumbnailPath)
                    }
                    migratedItems[index] = item
                }

                directoryURL = destinationDirectoryURL
                defaults.set(destinationDirectoryURL.path, forKey: Self.directoryKey)
                return ClipboardCacheMigration(items: migratedItems, legacyPaths: oldPaths)
            } catch {
                for copiedPath in copiedPaths {
                    try? fileManager.removeItem(atPath: copiedPath)
                }
                throw error
            }
        }
    }

    private func copyManagedFile(
        _ path: String,
        from oldDirectoryURL: URL,
        to destinationDirectoryURL: URL
    ) throws -> (path: String, didCopy: Bool)? {
        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
        guard
            sourceURL.path.hasPrefix(oldDirectoryURL.path + "/"),
            fileManager.fileExists(atPath: sourceURL.path),
            (try? sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        else {
            return nil
        }

        var destinationURL = destinationDirectoryURL.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: false
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = destinationDirectoryURL.appendingPathComponent(
                "migrated-\(UUID().uuidString)-\(sourceURL.lastPathComponent)",
                isDirectory: false
            )
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return (destinationURL.path, true)
    }

    private func makeDestinationLocked(extension fileExtension: String) -> URL? {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
            return directoryURL.appendingPathComponent(
                "item-\(UUID().uuidString)\(suffix)",
                isDirectory: false
            )
        } catch {
            JarvisPersistenceLog.logger.error(
                "创建剪贴板缓存目录失败：\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func usageLocked() -> ClipboardCacheUsage {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ClipboardCacheUsage(
                usedBytes: 0,
                capacityBytes: maximumBytes,
                fileCount: 0
            )
        }

        var usedBytes: Int64 = 0
        var fileCount = 0
        for case let url as URL in enumerator {
            guard
                let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                ),
                values.isRegularFile == true
            else {
                continue
            }
            usedBytes += Int64(values.fileSize ?? 0)
            fileCount += 1
        }
        return ClipboardCacheUsage(
            usedBytes: usedBytes,
            capacityBytes: maximumBytes,
            fileCount: fileCount
        )
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return support.appendingPathComponent("Jarvis/Clipboard", isDirectory: true)
    }

    static func normalizedMaximumBytes(_ value: Int64) -> Int64 {
        let clamped = min(max(value, minimumMaximumBytes), maximumMaximumBytes)
        return supportedMaximumBytes.min { lhs, rhs in
            abs(lhs - clamped) < abs(rhs - clamped)
        } ?? defaultMaximumBytes
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
