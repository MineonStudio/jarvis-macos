import Foundation

enum JarvisProtectedStorage {
    static func prepareDirectory(_ url: URL, fileManager: FileManager = .default) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Jarvis 在「应用支持」下的数据目录。
///
/// 每个存储原本各自拼一遍这段路径，而这几段拷贝已经开始各自演化。集中在这里
/// 之后，目录策略只有一种写法。
enum JarvisAppDirectory {
    static func url(
        _ component: String? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let root = support.appendingPathComponent(
            JarvisAppIdentity.dataDirectoryName,
            isDirectory: true
        )
        guard let component else { return root }
        return root.appendingPathComponent(component, isDirectory: true)
    }
}

/// 一份 JSON 文件，带锁、原子写与 0600 权限。
///
/// 在此之前每个存储都手写同一套脚手架：加锁、`fileExists` 守卫、编解码、原子写、
/// 失败记日志。那些差异不是有意设计，而是同一段代码拷贝之后各自演化的结果——壁纸
/// 元数据一度漏掉 0600，而几乎每一处在文件读不出来时都返回空值，紧接着的一次写入
/// 就把损坏内容连同用户数据一起覆盖掉。
///
/// 读的结果因此区分「还没有这份文件」和「有但读不出来」：前者是正常的首次运行，
/// 后者绝不能变成一次写入的基础。损坏的内容会被挪到一边留证，挪不动就拒绝写入。
final class JarvisJSONFile<Value: Codable & Sendable>: @unchecked Sendable {
    private enum Content {
        case missing
        case loaded(Value)
        /// 内容读不出来，而且没能挪开留证。任何写入都可能覆盖未知内容。
        case unreadable
    }

    let fileURL: URL
    /// 只在 `lock` 内使用。
    private let fileManager: FileManager
    private let logDomain: String
    private let logCategory: JarvisLogCategory
    private let lock = NSLock()
    /// 最近一次落盘的写入版本。去抖写入可能带着旧状态晚到，版本号让它在落盘前被
    /// 丢弃，不会覆盖更新的写入。
    private var appliedRevision: UInt64 = 0

    init(
        directoryURL: URL,
        fileName: String,
        logDomain: String,
        logCategory: JarvisLogCategory = .storage,
        fileManager: FileManager = .default
    ) {
        JarvisProtectedStorage.prepareDirectory(directoryURL, fileManager: fileManager)
        fileURL = directoryURL.appendingPathComponent(fileName)
        self.fileManager = fileManager
        self.logDomain = logDomain
        self.logCategory = logCategory
    }

    private func read() -> Content {
        lock.withLock { readLocked() }
    }

    /// - Parameter revision: 调用方读取待写入状态时分配的版本号。早于已落盘版本的
    ///   写入会被丢弃，`nil` 表示无条件写入。
    @discardableResult
    func write(_ value: Value, revision: UInt64? = nil) -> Bool {
        lock.withLock {
            if let revision {
                guard revision >= appliedRevision else {
                    JarvisLog.notice(
                        category: logCategory,
                        event: "\(logDomain).save.superseded",
                        result: "discarded",
                        fields: [
                            "revision": String(revision),
                            "appliedRevision": String(appliedRevision)
                        ]
                    )
                    return true
                }
                appliedRevision = revision
            }

            let operationID = JarvisLog.operationID()
            JarvisLog.debug(
                category: logCategory,
                event: "\(logDomain).save.begin",
                operationID: operationID,
                fields: ["path": JarvisLogRedactor.path(fileURL.path)]
            )
            do {
                let data = try JSONEncoder().encode(value)
                try JarvisProtectedStorage.write(data, to: fileURL)
                JarvisLog.info(
                    category: logCategory,
                    event: "\(logDomain).save.complete",
                    operationID: operationID,
                    result: "success",
                    fields: ["bytes": String(data.count)]
                )
                return true
            } catch {
                JarvisLog.error(
                    category: logCategory,
                    event: "\(logDomain).save.failed",
                    error: error,
                    operationID: operationID
                )
                return false
            }
        }
    }

    /// 与 `write` 相同，但把失败抛出来。调用方需要据此告诉用户「没保存成功」时用这个
    /// ——`write` 的返回值很容易被丢掉，那样失败的保存会报告成功。
    func writeOrThrow(_ value: Value, revision: UInt64? = nil) throws {
        guard write(value, revision: revision) else {
            throw JarvisJSONFileError.writeFailed
        }
    }

    /// 只读场景：还没有内容或读不出来，都当作缺少内容。
    func readOrDefault(_ defaultValue: Value) -> Value {
        guard case let .loaded(value) = read() else { return defaultValue }
        return value
    }

    /// 写入所依据的内容。首次运行没有文件时给出 `defaultValue`，但读不出来又留不下
    /// 证据时会报错——那时交出一个空值就等于让调用方覆盖掉未知内容。
    func readForWriting(default defaultValue: Value) throws -> Value {
        switch read() {
        case .missing:
            defaultValue
        case let .loaded(value):
            value
        case .unreadable:
            throw JarvisJSONFileError.unreadable
        }
    }

    private func readLocked() -> Content {
        let operationID = JarvisLog.operationID()
        JarvisLog.debug(
            category: logCategory,
            event: "\(logDomain).load.begin",
            operationID: operationID,
            fields: ["path": JarvisLogRedactor.path(fileURL.path)]
        )

        guard fileManager.fileExists(atPath: fileURL.path) else {
            JarvisLog.info(
                category: logCategory,
                event: "\(logDomain).load.complete",
                operationID: operationID,
                result: "empty"
            )
            return .missing
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let value = try JSONDecoder().decode(Value.self, from: data)
            JarvisLog.info(
                category: logCategory,
                event: "\(logDomain).load.complete",
                operationID: operationID,
                result: "success",
                fields: ["bytes": String(data.count)]
            )
            return .loaded(value)
        } catch {
            JarvisLog.error(
                category: logCategory,
                event: "\(logDomain).load.failed",
                error: error,
                operationID: operationID,
                fields: ["path": JarvisLogRedactor.path(fileURL.path)]
            )
            let quarantined = quarantineUnreadableFile()
            JarvisLog.notice(
                category: logCategory,
                event: "\(logDomain).load.quarantine",
                operationID: operationID,
                result: quarantined ? "preserved" : "failed"
            )
            return quarantined ? .missing : .unreadable
        }
    }

    /// 把读不出来的内容挪到一边留证，让后续写入不再覆盖未知内容。
    /// - Returns: 是否成功挪开。失败时调用方必须拒绝写入。
    private func quarantineUnreadableFile() -> Bool {
        // 后缀插在扩展名之前，留证的文件仍然是个 .json；带随机尾号是为了让同一秒内
        // 的二次损坏不会因为重名而挪不动。
        let base = fileURL.deletingPathExtension().lastPathComponent
        let extensionName = fileURL.pathExtension
        let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let quarantineURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(stamp).\(extensionName)")
        return (try? fileManager.moveItem(at: fileURL, to: quarantineURL)) != nil
    }
}

enum JarvisJSONFileError: LocalizedError, Equatable {
    /// 已有内容读不出来，且没能挪开留证，所以拒绝写入。
    case unreadable
    /// 内容本身没问题，但没能写到磁盘上。
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: "已有数据无法读取，为避免覆盖已暂停保存"
        case .writeFailed: "无法写入磁盘，改动没有保存"
        }
    }
}
