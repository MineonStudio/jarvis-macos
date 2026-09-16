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

    func append(_ event: JarvisLogEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        let line = data + Data([0x0A])

        lock.withLock {
            withProcessLock {
                prepareDirectory()
                let shouldRotateForNewDay = (try? fileManager.attributesOfItem(atPath: currentFileURL.path))
                    .flatMap { $0[.modificationDate] as? Date }
                    .map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: Date()) }
                    ?? false
                rotateIfNeeded(for: line.count, force: shouldRotateForNewDay)
                if !fileManager.fileExists(atPath: currentFileURL.path),
                   !fileManager.createFile(atPath: currentFileURL.path, contents: nil)
                {
                    return
                }

                do {
                    let handle = try FileHandle(forWritingTo: currentFileURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                    try handle.close()
                    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: currentFileURL.path)
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

    private func rotateIfNeeded(for incomingBytes: Int, force: Bool) {
        let currentBytes = (try? fileManager.attributesOfItem(atPath: currentFileURL.path))
            .flatMap { $0[.size] as? NSNumber }
            .map(\.int64Value)
            ?? 0
        guard force || currentBytes + Int64(incomingBytes) > maximumFileBytes
        else {
            return
        }

        guard maximumFileCount > 1 else {
            try? fileManager.removeItem(at: currentFileURL)
            return
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

    init() {
        localStore = JarvisLocalLogStore()
        debugEnabled = ProcessInfo.processInfo.environment["JARVIS_DEBUG_LOGS"] == "1"
    }

    func configure(localStore: JarvisLocalLogStore, debugEnabled: Bool? = nil) {
        lock.withLock {
            self.localStore = localStore
            if let debugEnabled {
                self.debugEnabled = debugEnabled
            }
        }
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
        let (store, debugEnabled) = lock.withLock { (localStore, self.debugEnabled) }
        guard level != .debug || debugEnabled else { return }

        let safeFields = JarvisLogRedactor.fields(fields)
        let logEvent = JarvisLogEvent(
            schemaVersion: JarvisLogEvent.currentSchemaVersion,
            timestamp: Self.timestamp(),
            level: level,
            category: category,
            event: event,
            sessionID: JarvisLogContext.sessionID,
            operationID: operationID,
            processID: ProcessInfo.processInfo.processIdentifier,
            bundleID: JarvisAppIdentity.bundleIdentifier,
            bundlePath: JarvisLogRedactor.path(Bundle.main.bundleURL.path),
            appVersion: JarvisAppVersion.shortVersion,
            build: JarvisAppVersion.build,
            durationMilliseconds: durationMilliseconds,
            result: result.map(JarvisLogRedactor.text),
            fields: safeFields
        )

        let messageFields = safeFields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let renderedMessage = messageFields.isEmpty ? event : "\(event) \(messageFields)"
        Logger(subsystem: JarvisAppIdentity.bundleIdentifier, category: category.rawValue)
            .log(level: level.osLogType, "\(renderedMessage, privacy: .public)")
        store.append(logEvent)
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
