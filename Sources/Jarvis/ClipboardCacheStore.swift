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

struct ClipboardCacheUsage: Equatable, Sendable {
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

struct ClipboardCacheAudit: Codable, Equatable, Sendable {
    let historyCount: Int
    let referenceCount: Int
    let missingReferenceCount: Int
    let missingByKind: [String: Int]
    let missingByReferenceType: [String: Int]
    let unusableRecordCount: Int
    let cacheFileCount: Int
    let cacheBytes: Int64
    let capacityBytes: Int64

    var usableRecordCount: Int {
        max(historyCount - unusableRecordCount, 0)
    }

    func logFields(autoCleanupEnabled: Bool) -> [String: String] {
        [
            "historyCount": String(historyCount),
            "referenceCount": String(referenceCount),
            "missingReferenceCount": String(missingReferenceCount),
            "missingByKind": missingByKind
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ","),
            "missingByReferenceType": missingByReferenceType
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ","),
            "usableRecordCount": String(usableRecordCount),
            "unusableRecordCount": String(unusableRecordCount),
            "cacheFileCount": String(cacheFileCount),
            "cacheBytes": String(cacheBytes),
            "capacityBytes": String(capacityBytes),
            "autoCleanupEnabled": String(autoCleanupEnabled)
        ]
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

        JarvisProtectedStorage.prepareDirectory(directoryURL, fileManager: fileManager)
        JarvisLog.info(
            category: .clipboard,
            event: "cache.initialized",
            fields: [
                "directory": JarvisLogRedactor.path(directoryURL.path),
                "configuredDirectory": String(storedDirectory != nil),
                "capacityBytes": String(maximumBytes)
            ]
        )
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
        JarvisLog.info(
            category: .clipboard,
            event: "cache.capacityChanged",
            fields: ["capacityBytes": String(clamped)]
        )
    }

    func usage() -> ClipboardCacheUsage {
        lock.withLock { usageLocked() }
    }

    func audit(items: [ClipboardItem]) -> ClipboardCacheAudit {
        lock.withLock {
            var referenceCount = 0
            var missingReferenceCount = 0
            var missingByKind = Dictionary(
                uniqueKeysWithValues: ClipboardKind.allCases.map { ($0.rawValue, 0) }
            )
            var missingByReferenceType = [
                "textPath": 0,
                "imagePath": 0,
                "filePath": 0,
                "thumbnailPath": 0
            ]
            var unusableRecordCount = 0

            for item in items {
                let references: [(String, String)] = [
                    ("textPath", item.textPath),
                    ("imagePath", item.imagePath),
                    ("filePath", item.filePath),
                    ("thumbnailPath", item.thumbnailPath)
                ].compactMap { name, path in
                    path.map { (name, $0) }
                }
                referenceCount += references.count
                for (referenceType, path) in references where !fileManager.fileExists(atPath: path) {
                    missingReferenceCount += 1
                    missingByKind[item.kind.rawValue, default: 0] += 1
                    missingByReferenceType[referenceType, default: 0] += 1
                }

                let isUsable: Bool = switch item.kind {
                case .text:
                    item.text != nil
                        || (item.textPath.map { fileManager.fileExists(atPath: $0) } ?? false)
                case .image:
                    item.imagePath.map { fileManager.fileExists(atPath: $0) } ?? false
                case .file, .video:
                    item.filePath.map { fileManager.fileExists(atPath: $0) } ?? false
                }
                if !isUsable {
                    unusableRecordCount += 1
                }
            }

            let usage = usageLocked()
            return ClipboardCacheAudit(
                historyCount: items.count,
                referenceCount: referenceCount,
                missingReferenceCount: missingReferenceCount,
                missingByKind: missingByKind,
                missingByReferenceType: missingByReferenceType,
                unusableRecordCount: unusableRecordCount,
                cacheFileCount: usage.fileCount,
                cacheBytes: usage.usedBytes,
                capacityBytes: usage.capacityBytes
            )
        }
    }

    func storeFile(_ sourceURL: URL, fileSize: Int64) -> String? {
        let operationID = JarvisLog.operationID()
        let startedAt = Date()
        JarvisLog.debug(
            category: .clipboard,
            event: "cache.write.begin",
            operationID: operationID,
            fields: [
                "kind": "file",
                "requestedBytes": String(fileSize),
                "extension": sourceURL.pathExtension.lowercased()
            ]
        )
        let destination: URL? = lock.withLock {
            guard
                let values = try? sourceURL.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                ),
                values.isRegularFile == true,
                let sourceSize = values.fileSize,
                sourceSize >= 0,
                Int64(sourceSize) <= maximumBytes,
                usageLocked().usedBytes + Int64(sourceSize) <= maximumBytes
            else {
                return nil
            }
            return makeDestinationLocked(extension: sourceURL.pathExtension)
        }
        guard let destination else {
            JarvisLog.notice(
                category: .clipboard,
                event: "cache.write.rejected",
                operationID: operationID,
                result: "capacityOrSourceRejected",
                fields: [
                    "kind": "file",
                    "requestedBytes": String(fileSize)
                ]
            )
            return nil
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
            JarvisLog.info(
                category: .clipboard,
                event: "cache.write.complete",
                operationID: operationID,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
                result: "success",
                fields: [
                    "kind": "file",
                    "bytes": String(fileSize),
                    "destination": JarvisLogRedactor.path(destination.path)
                ]
            )
            return destination.path
        } catch {
            try? fileManager.removeItem(at: destination)
            JarvisLog.error(
                category: .clipboard,
                event: "cache.write.failed",
                error: error,
                operationID: operationID,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
                fields: ["kind": "file"]
            )
            return nil
        }
    }

    func storeData(_ data: Data, fileExtension: String) -> String? {
        let operationID = JarvisLog.operationID()
        let startedAt = Date()
        JarvisLog.debug(
            category: .clipboard,
            event: "cache.write.begin",
            operationID: operationID,
            fields: [
                "kind": fileExtension.lowercased() == "txt" ? "text" : "image",
                "requestedBytes": String(data.count),
                "extension": fileExtension.lowercased()
            ]
        )
        let destination: URL? = lock.withLock {
            let dataSize = Int64(data.count)
            guard
                dataSize <= maximumBytes,
                usageLocked().usedBytes + dataSize <= maximumBytes
            else {
                return nil
            }
            return makeDestinationLocked(extension: fileExtension)
        }
        guard let destination else {
            JarvisLog.notice(
                category: .clipboard,
                event: "cache.write.rejected",
                operationID: operationID,
                result: "capacityExceeded",
                fields: [
                    "kind": fileExtension.lowercased() == "txt" ? "text" : "image",
                    "requestedBytes": String(data.count)
                ]
            )
            return nil
        }

        do {
            try JarvisProtectedStorage.write(data, to: destination)
            JarvisLog.info(
                category: .clipboard,
                event: "cache.write.complete",
                operationID: operationID,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
                result: "success",
                fields: [
                    "kind": fileExtension.lowercased() == "txt" ? "text" : "image",
                    "bytes": String(data.count),
                    "destination": JarvisLogRedactor.path(destination.path)
                ]
            )
            return destination.path
        } catch {
            try? fileManager.removeItem(at: destination)
            JarvisLog.error(
                category: .clipboard,
                event: "cache.write.failed",
                error: error,
                operationID: operationID,
                durationMilliseconds: Date().timeIntervalSince(startedAt) * 1000,
                fields: [
                    "kind": fileExtension.lowercased() == "txt" ? "text" : "image",
                    "bytes": String(data.count)
                ]
            )
            return nil
        }
    }

    func removeStoredFile(atPath path: String) {
        let operationID = JarvisLog.operationID()
        do {
            try fileManager.removeItem(atPath: path)
            JarvisLog.info(
                category: .clipboard,
                event: "cache.fileDelete.complete",
                operationID: operationID,
                result: "success",
                fields: ["path": JarvisLogRedactor.path(path)]
            )
        } catch CocoaError.fileNoSuchFile {
            JarvisLog.notice(
                category: .clipboard,
                event: "cache.fileDelete.complete",
                operationID: operationID,
                result: "alreadyMissing",
                fields: ["path": JarvisLogRedactor.path(path)]
            )
        } catch {
            JarvisLog.error(
                category: .clipboard,
                event: "cache.fileDelete.failed",
                error: error,
                operationID: operationID,
                fields: ["path": JarvisLogRedactor.path(path)]
            )
        }
    }

    func removeLegacyFiles(atPaths paths: [String], reason: String = "legacyCleanup") {
        guard !paths.isEmpty else { return }
        JarvisLog.debug(
            category: .clipboard,
            event: "cache.legacyDelete.begin",
            fields: [
                "pathCount": String(paths.count),
                "reason": reason
            ]
        )
        for path in paths {
            removeStoredFile(atPath: path)
        }
        JarvisLog.info(
            category: .clipboard,
            event: "cache.legacyDelete.complete",
            result: "success",
            fields: [
                "pathCount": String(paths.count),
                "reason": reason
            ]
        )
    }

    /// Removes only files owned by the configured cache directory.
    /// External source files referenced by clipboard history are never touched.
    @discardableResult
    func removeManagedFiles(for items: [ClipboardItem], reason: String = "manual") -> Bool {
        let operationID = JarvisLog.operationID()
        let result = lock.withLock {
            var succeeded = true
            var removedFileCount = 0
            for item in items {
                for url in managedFileURLsLocked(for: item) {
                    guard fileManager.fileExists(atPath: url.path) else { continue }
                    do {
                        try fileManager.removeItem(at: url)
                        removedFileCount += 1
                    } catch {
                        succeeded = false
                        JarvisLog.error(
                            category: .clipboard,
                            event: "cache.delete.failed",
                            error: error,
                            operationID: operationID,
                            fields: [
                                "reason": reason,
                                "kind": item.kind.rawValue
                            ]
                        )
                    }
                }
            }
            return (
                succeeded
                    && items.allSatisfy { managedFileURLsLocked(for: $0).allSatisfy { !fileManager.fileExists(atPath: $0.path) } },
                removedFileCount
            )
        }
        JarvisLog.info(
            category: .clipboard,
            event: "cache.delete.complete",
            operationID: operationID,
            result: result.0 ? "success" : "partialFailure",
            fields: [
                "reason": reason,
                "itemCount": String(items.count),
                "fileCount": String(result.1)
            ]
        )
        return result.0
    }

    func hasManagedFiles(for item: ClipboardItem) -> Bool {
        lock.withLock {
            managedFileURLsLocked(for: item).contains { fileManager.fileExists(atPath: $0.path) }
        }
    }

    /// Returns whether the history item still points at a path owned by the
    /// configured cache directory, even when that file has already gone
    /// missing. Cleanup needs this distinction so stale history records can
    /// be removed after the cache directory was cleared externally.
    func hasManagedReferences(for item: ClipboardItem) -> Bool {
        lock.withLock {
            !managedFileURLsLocked(for: item).isEmpty
        }
    }

    @discardableResult
    func removeOrphanedManagedFiles(
        referencedPaths: Set<String>,
        olderThan: Date? = nil,
        reason: String = "orphanCleanup"
    ) -> Bool {
        let operationID = JarvisLog.operationID()
        let removed: (Bool, Int) = lock.withLock {
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return (false, 0)
            }

            let referenced = Set(referencedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
            var didRemove = false
            var removedFileCount = 0
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
                    didRemove = true
                    removedFileCount += 1
                } catch {
                    JarvisLog.error(
                        category: .clipboard,
                        event: "cache.orphanDelete.failed",
                        error: error,
                        operationID: operationID,
                        fields: ["reason": reason]
                    )
                }
            }
            return (didRemove, removedFileCount)
        }
        JarvisLog.info(
            category: .clipboard,
            event: "cache.orphanDelete.complete",
            operationID: operationID,
            result: "success",
            fields: [
                "reason": reason,
                "fileCount": String(removed.1)
            ]
        )
        return removed.0
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
        let operationID = JarvisLog.operationID()
        let oldDirectory = currentDirectoryURL
        let destinationDirectory = newDirectoryURL.standardizedFileURL
        JarvisLog.notice(
            category: .clipboard,
            event: "cache.migration.begin",
            operationID: operationID,
            fields: [
                "sourceDirectory": JarvisLogRedactor.path(oldDirectory.path),
                "destinationDirectory": JarvisLogRedactor.path(destinationDirectory.path),
                "itemCount": String(items.count)
            ]
        )

        do {
            let migration = try lock.withLock {
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
            JarvisLog.info(
                category: .clipboard,
                event: "cache.migration.complete",
                operationID: operationID,
                result: "success",
                fields: [
                    "itemCount": String(migration.items.count),
                    "legacyPathCount": String(migration.legacyPaths.count)
                ]
            )
            return migration
        } catch {
            JarvisLog.error(
                category: .clipboard,
                event: "cache.migration.failed",
                error: error,
                operationID: operationID,
                fields: ["itemCount": String(items.count)]
            )
            throw error
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
            JarvisLog.error(
                category: .clipboard,
                event: "cache.directoryCreate.failed",
                error: error
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
        return support.appendingPathComponent(
            "\(JarvisAppIdentity.dataDirectoryName)/Clipboard",
            isDirectory: true
        )
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

/// 缓存容量的文字表述与比例。
///
/// 原本长在设置卡片里，视图层不该承担这个，而 `ClipboardCacheStore` 才是定义这些
/// 容量含义的地方。
enum ClipboardCacheFormatting {
    static func byteDescription(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }

    /// 容量上限用整 GB 表述更易读，最小档则固定写成 256 MB。
    static func capacityDescription(_ bytes: Int64) -> String {
        if bytes == ClipboardCacheStore.minimumMaximumBytes {
            return "256 MB"
        }
        let gigabyte: Int64 = 1024 * 1024 * 1024
        if bytes % gigabyte == 0 {
            return "\(bytes / gigabyte) GB"
        }
        return byteDescription(bytes)
    }
}
