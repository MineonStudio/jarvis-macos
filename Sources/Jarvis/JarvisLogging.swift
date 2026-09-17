import CryptoKit
import Darwin
import Foundation
import OSLog

enum JarvisLogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case notice
    case error
    case fault

    var osLogType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        case .fault: .fault
        }
    }
}

enum JarvisLogCategory: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case clipboard
    case meeting
    case storage
    case window
    case shortcut
    case network
    case update
    case performance
    case security
}

struct JarvisLogEvent: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let timestamp: String
    let level: JarvisLogLevel
    let category: JarvisLogCategory
    let event: String
    let sessionID: String
    let operationID: String?
    let processID: Int32
    let bundleID: String
    let bundlePath: String
    let appVersion: String
    let build: String
    let durationMilliseconds: Double?
    let result: String?
    let fields: [String: String]

    static let currentSchemaVersion = 1
}

enum JarvisLogRedactor {
    private static let homeURL = FileManager.default.homeDirectoryForCurrentUser
    private static let applicationSupportURL = homeURL
        .appendingPathComponent("Library/Application Support", isDirectory: true)
        .standardizedFileURL
    private static let logURL = homeURL
        .appendingPathComponent("Library/Logs/Jarvis", isDirectory: true)
        .standardizedFileURL

    static func path(_ rawPath: String) -> String {
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        let path = url.path

        if path == homeURL.path || path.hasPrefix(homeURL.path + "/") {
            let relative = String(path.dropFirst(homeURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if path.hasPrefix(applicationSupportURL.path + "/") || path.hasPrefix(logURL.path + "/") {
                return "~/\(relative)"
            }

            let extensionPart = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension.lowercased())"
            return "<home-file>\(extensionPart)#\(shortHash(path))"
        }

        let extensionPart = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension.lowercased())"
        return "<external-file>\(extensionPart)#\(shortHash(path))"
    }

    /// 一条脱敏规则。正则预先编译一次。
    ///
    /// 这里原本用 `replacingOccurrences(options: .regularExpression)`，那个 API 每次
    /// 调用都要现场编译正则，而脱敏在每条日志的每个字段上都会跑一遍——一条日志就是
    /// 六次编译。
    private struct TextRule {
        let regex: NSRegularExpression
        let replacement: String

        /// 模式写错时跳过这条规则，与 `replacingOccurrences` 的行为一致（它遇到无效
        /// 模式也是原样返回）。`LoggingTests` 逐条验证每个模式都还在生效。
        init?(_ pattern: String, _ replacement: String) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            self.regex = regex
            self.replacement = replacement
        }
    }

    private static let textRules: [TextRule] = [
        TextRule(#"(?i)https?://[^\s]+"#, "<url>"),
        TextRule(#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#, "<email>"),
        TextRule(
            #"(?i)(?:api[_-]?key|access[_-]?token|auth(?:orization)?|bearer|secret|password|passwd|cookie|private[_-]?key)\s*[:=]\s*[^\s,;]+"#,
            "<credential>"
        ),
        TextRule(#"(?:/Users/[^\s]+|/private/var/[^\s]+|/var/folders/[^\s]+)"#, "<path>"),
        TextRule(#"\b(?:eyJ[A-Za-z0-9_-]{10,}\.){2}[A-Za-z0-9_-]{10,}\b"#, "<jwt>"),
        TextRule(#"\b[A-Za-z0-9_-]{32,}\b"#, "<opaque>")
    ].compactMap { $0 }

    static func text(_ value: String) -> String {
        var result = value
        for rule in textRules {
            result = rule.regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.replacement
            )
        }
        return result
    }

    static func fields(_ fields: [String: String]) -> [String: String] {
        fields.reduce(into: [:]) { result, entry in
            let key = entry.key.lowercased()
            if ["clipboard", "clipboardtext", "content", "message", "payload", "preview", "text"].contains(where: key.contains) {
                result[entry.key] = "<redacted>"
            } else if key.contains("path") || key.contains("filename") {
                result[entry.key] = path(entry.value)
            } else {
                result[entry.key] = text(entry.value)
            }
        }
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}

final class JarvisLocalLogStore: @unchecked Sendable {
    static let defaultDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Jarvis", isDirectory: true)

    let directoryURL: URL
    let maximumFileBytes: Int64
    let maximumFileCount: Int

    private let fileManager: FileManager
    private let lock = NSLock()
    private var fileLockDescriptor: Int32 = -1

    init(
        directoryURL: URL = JarvisLocalLogStore.defaultDirectoryURL,
        maximumFileBytes: Int64 = 10 * 1024 * 1024,
        maximumFileCount: Int = 5,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.maximumFileBytes = max(maximumFileBytes, 1)
        self.maximumFileCount = max(maximumFileCount, 1)
        self.fileManager = fileManager
        prepareDirectory()
        fileLockDescriptor = Darwin.open(
            directoryURL.appendingPathComponent(".events.lock", isDirectory: false).path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
    }

    deinit {
        guard fileLockDescriptor >= 0 else { return }
        close(fileLockDescriptor)
    }

    var eventFileURLs: [URL] {
        lock.withLock {
            (0 ..< maximumFileCount).map { index in
                index == 0
                    ? currentFileURL
                    : rotatedFileURL(index: index)
            }.filter { fileManager.fileExists(atPath: $0.path) }
        }
    }

    /// 一批事件共用一次锁、一次轮转判断和一次 open/write/close。逐条写时每行要付
    /// 十来个系统调用（含 `flock`、`chmod`、`createDirectory`），卡顿日志一多就把
    /// 调用线程拖住——而卡顿日志恰恰是在主线程卡住时产生的。
    ///
    /// 只保留批量入口：单条转发的重载会诱使新调用方回到逐条写盘的旧路。
    func append(_ events: [JarvisLogEvent]) {
        let encoder = JSONEncoder()
        var payload = Data()
        for event in events {
            guard let data = try? encoder.encode(event) else { continue }
            payload.append(data)
            payload.append(0x0A)
        }
        guard !payload.isEmpty else { return }

        lock.withLock {
            withProcessLock {
                // 一次 `attributesOfItem` 就同时给出「文件在不在、多大、多久没写」，
                // 顶掉原来的三次 stat 和一次 fileExists。
                let existing = try? fileManager.attributesOfItem(atPath: currentFileURL.path)
                let shouldRotateForNewDay = (existing?[.modificationDate] as? Date)
                    .map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: Date()) }
                    ?? false
                let existingBytes = (existing?[.size] as? NSNumber)?.int64Value ?? 0
                let didRotate = rotateIfNeeded(
                    currentBytes: existingBytes,
                    incomingBytes: payload.count,
                    force: shouldRotateForNewDay
                )
                // 只有真的要新建文件时才补目录和权限：目录被清掉或刚轮转过，文件才不在。
                let needsNewFile = existing == nil || didRotate
                if needsNewFile {
                    prepareDirectory()
                    guard fileManager.createFile(atPath: currentFileURL.path, contents: nil) else {
                        return
                    }
                }

                do {
                    let handle = try FileHandle(forWritingTo: currentFileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: payload)
                    try handle.close()
                    if needsNewFile {
                        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: currentFileURL.path)
                    }
                } catch {
                    // Logging must never recursively log its own I/O failure.
                }
            }
        }
    }

    private func withProcessLock(_ body: () -> Void) {
        guard fileLockDescriptor >= 0, flock(fileLockDescriptor, LOCK_EX) == 0 else {
            body()
            return
        }
        defer { flock(fileLockDescriptor, LOCK_UN) }
        body()
    }

    private var currentFileURL: URL {
        directoryURL.appendingPathComponent("events.ndjson", isDirectory: false)
    }

    private func rotatedFileURL(index: Int) -> URL {
        directoryURL.appendingPathComponent("events.ndjson.\(index)", isDirectory: false)
    }

    private func prepareDirectory() {
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
    }

    /// 返回是否真的轮转过——调用方据此判断当前文件是否已经不在了。
    @discardableResult
    private func rotateIfNeeded(currentBytes: Int64, incomingBytes: Int, force: Bool) -> Bool {
        guard force || currentBytes + Int64(incomingBytes) > maximumFileBytes
        else {
            return false
        }

        guard maximumFileCount > 1 else {
            try? fileManager.removeItem(at: currentFileURL)
            return true
        }

        for index in stride(from: maximumFileCount - 1, through: 2, by: -1) {
            let source = rotatedFileURL(index: index - 1)
            let destination = rotatedFileURL(index: index)
            try? fileManager.removeItem(at: destination)
            if fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: source, to: destination)
            }
        }
        let firstRotation = rotatedFileURL(index: 1)
        try? fileManager.removeItem(at: firstRotation)
        if fileManager.fileExists(atPath: currentFileURL.path) {
            try? fileManager.moveItem(at: currentFileURL, to: firstRotation)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: firstRotation.path)
        return true
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private final class JarvisLogRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var localStore: JarvisLocalLogStore
    private var debugEnabled: Bool
    /// 已投递但还没落盘的事件数（`lock` 保护）：给 `flush()` 一个队列空时直接返回的
    /// 机会，不必每次都在主线程上同步等一趟。
    private var pendingWriteCount = 0

    /// 脱敏、JSON 编码、OSLog、文件 I/O 全部挪到这条串行队列：调用方只投递一次
    /// `async` 就返回。写盘按批合并，一批只开一次文件。
    private let writerQueue = DispatchQueue(
        label: "\(JarvisAppIdentity.bundleIdentifier).log-writer",
        qos: .utility
    )
    private static let writerQueueKey = DispatchSpecificKey<Void>()
    /// 下面两个只在 `writerQueue` 上访问。
    private var pendingEvents: [JarvisLogEvent] = []
    private var scheduledFlush: DispatchWorkItem?
    private static let maximumBatchSize = 32
    private static let flushDelay = DispatchTimeInterval.milliseconds(250)

    /// 进程内不会变的字段算一次就够。原来每条日志都要重算一遍路径哈希和几次
    /// `Bundle` 查询——都发生在 `flush()` 还在主线程上等着的那条队列里。
    private static let bundleIdentifierValue = JarvisAppIdentity.bundleIdentifier
    private static let bundlePathValue = JarvisLogRedactor.path(Bundle.main.bundleURL.path)
    private static let processIdentifierValue = ProcessInfo.processInfo.processIdentifier
    private static let appVersionValue = JarvisAppVersion.shortVersion
    private static let buildValue = JarvisAppVersion.build

    init() {
        localStore = JarvisLocalLogStore()
        debugEnabled = ProcessInfo.processInfo.environment["JARVIS_DEBUG_LOGS"] == "1"
        writerQueue.setSpecific(key: Self.writerQueueKey, value: ())
    }

    var eventFileURLs: [URL] {
        lock.withLock { localStore }.eventFileURLs
    }

    func configure(localStore: JarvisLocalLogStore, debugEnabled: Bool? = nil) {
        // 换存储前先把旧存储的待写事件落盘，避免它们落到新文件里。
        flush()
        lock.withLock {
            self.localStore = localStore
            if let debugEnabled {
                self.debugEnabled = debugEnabled
            }
        }
    }

    /// 等待已投递的日志落盘。测试、退出前、导出诊断包前调用。
    func flush() {
        guard DispatchQueue.getSpecific(key: Self.writerQueueKey) == nil else {
            writePendingEvents()
            return
        }
        guard lock.withLock({ pendingWriteCount > 0 }) else {
            return
        }
        writerQueue.sync { writePendingEvents() }
    }

    func emit(
        level: JarvisLogLevel,
        category: JarvisLogCategory,
        event: String,
        operationID: String?,
        durationMilliseconds: Double?,
        result: String?,
        fields: [String: String]
    ) {
        let debugEnabled = lock.withLock { self.debugEnabled }
        guard level != .debug || debugEnabled else { return }
        // 时间戳必须在调用现场取：挪到写队列上就成了“队列排到它”的时刻，积压时
        // 会晚好几秒，和事件自己记录的 durationMilliseconds 对不上。
        let timestamp = Self.timestamp()
        // 错误和崩溃不等合并窗口，强退或掉电也不会把现场丢掉。
        let shouldWriteImmediately = level == .fault || level == .error
        lock.withLock { pendingWriteCount += 1 }

        writerQueue.async { [self] in
            let safeFields = JarvisLogRedactor.fields(fields)
            let logEvent = JarvisLogEvent(
                schemaVersion: JarvisLogEvent.currentSchemaVersion,
                timestamp: timestamp,
                level: level,
                category: category,
                event: event,
                sessionID: JarvisLogContext.sessionID,
                operationID: operationID,
                processID: Self.processIdentifierValue,
                bundleID: Self.bundleIdentifierValue,
                bundlePath: Self.bundlePathValue,
                appVersion: Self.appVersionValue,
                build: Self.buildValue,
                durationMilliseconds: durationMilliseconds,
                result: result.map(JarvisLogRedactor.text),
                fields: safeFields
            )

            let messageFields = safeFields.sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            let renderedMessage = messageFields.isEmpty ? event : "\(event) \(messageFields)"
            Logger(subsystem: Self.bundleIdentifierValue, category: category.rawValue)
                .log(level: level.osLogType, "\(renderedMessage, privacy: .public)")

            pendingEvents.append(logEvent)
            if shouldWriteImmediately || pendingEvents.count >= Self.maximumBatchSize {
                writePendingEvents()
            } else {
                scheduleFlush()
            }
        }
    }

    /// 只在 `writerQueue` 上调用。存储在这里解析：这样 `configure` 的
    /// “先 flush 再换” 才成立——排在它前面的块写旧存储，排在后面的写新存储。
    private func writePendingEvents() {
        scheduledFlush?.cancel()
        scheduledFlush = nil
        let events = pendingEvents
        pendingEvents.removeAll(keepingCapacity: true)
        guard !events.isEmpty else { return }

        lock.withLock { localStore }.append(events)
        lock.withLock { pendingWriteCount = max(0, pendingWriteCount - events.count) }
    }

    /// 只在 `writerQueue` 上调用。定时器由 `scheduledFlush` 独占：直接写盘的分支
    /// 会把它取消掉，不会留下一个还在计时的旧定时器再冲一次盘。
    private func scheduleFlush() {
        guard scheduledFlush == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.writePendingEvents()
        }
        scheduledFlush = work
        writerQueue.asyncAfter(deadline: .now() + Self.flushDelay, execute: work)
    }

    /// `ISO8601DateFormatter` 的构造要加载 locale 数据，而每条日志都要取一次时间，
    /// 所以共用一份。日志来自多个线程，`DateFormatter` 有明确的线程安全保证、
    /// `ISO8601DateFormatter` 没有，这里不赌，加锁。
    private nonisolated(unsafe) static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 上一行的 `nonisolated(unsafe)` 由这把锁兜底：格式化只在锁内发生。
    private static let timestampLock = NSLock()

    private static func timestamp() -> String {
        timestampLock.withLock {
            timestampFormatter.string(from: Date())
        }
    }
}

enum JarvisLogContext {
    static let sessionID = UUID().uuidString.lowercased()
}

enum JarvisLog {
    static let sessionID = JarvisLogContext.sessionID
    private static let runtime = JarvisLogRuntime()

    static func configure(localStore: JarvisLocalLogStore, debugEnabled: Bool? = nil) {
        runtime.configure(localStore: localStore, debugEnabled: debugEnabled)
    }

    /// 日志写入是异步批量的，需要立刻读到文件时（测试、退出前、导出诊断包前）先调它。
    static func flush() {
        runtime.flush()
    }

    /// 当前真正在写的存储里的日志文件。导出诊断包要用它——新建一个默认存储会把
    /// `flush()` 冲刷的位置和实际打包的位置拆成两处。
    static var eventFileURLs: [URL] {
        runtime.eventFileURLs
    }

    static func operationID() -> String {
        UUID().uuidString.lowercased()
    }

    static func debug(
        category: JarvisLogCategory,
        event: String,
        operationID: String? = nil,
        durationMilliseconds: Double? = nil,
        result: String? = nil,
        fields: [String: String] = [:]
    ) {
        emit(
            level: .debug,
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: result,
            fields: fields
        )
    }

    static func info(
        category: JarvisLogCategory,
        event: String,
        operationID: String? = nil,
        durationMilliseconds: Double? = nil,
        result: String? = nil,
        fields: [String: String] = [:]
    ) {
        emit(
            level: .info,
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: result,
            fields: fields
        )
    }

    static func notice(
        category: JarvisLogCategory,
        event: String,
        operationID: String? = nil,
        durationMilliseconds: Double? = nil,
        result: String? = nil,
        fields: [String: String] = [:]
    ) {
        emit(
            level: .notice,
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: result,
            fields: fields
        )
    }

    static func error(
        category: JarvisLogCategory,
        event: String,
        operationID: String? = nil,
        durationMilliseconds: Double? = nil,
        result: String? = nil,
        fields: [String: String] = [:]
    ) {
        emit(
            level: .error,
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: result,
            fields: fields
        )
    }

    static func error(
        category: JarvisLogCategory,
        event: String,
        error: Error,
        operationID: String? = nil,
        durationMilliseconds: Double? = nil,
        fields: [String: String] = [:]
    ) {
        let nsError = error as NSError
        var enrichedFields = fields
        enrichedFields["errorDomain"] = nsError.domain
        enrichedFields["errorCode"] = String(nsError.code)
        enrichedFields["errorDescription"] = nsError.localizedDescription
        self.error(
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: "failure",
            fields: enrichedFields
        )
    }

    static func fault(
        category: JarvisLogCategory,
        event: String,
        operationID: String? = nil,
        durationMilliseconds: Double? = nil,
        result: String? = nil,
        fields: [String: String] = [:]
    ) {
        emit(
            level: .fault,
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: result,
            fields: fields
        )
    }

    private static func emit(
        level: JarvisLogLevel,
        category: JarvisLogCategory,
        event: String,
        operationID: String?,
        durationMilliseconds: Double?,
        result: String?,
        fields: [String: String]
    ) {
        runtime.emit(
            level: level,
            category: category,
            event: event,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            result: result,
            fields: fields
        )
    }
}
