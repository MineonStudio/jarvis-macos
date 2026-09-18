import Foundation

struct JarvisDiagnosticsManifest: Codable, Sendable {
    let schemaVersion: Int
    let generatedAt: String
    let appVersion: String
    let build: String
    let bundleID: String
    let bundlePath: String
    let processID: Int32
    let sessionID: String
    let includesClipboardContent: Bool
    let logFileNames: [String]
    let cacheAutoCleanupEnabled: Bool?
    let cacheAudit: ClipboardCacheAudit?
}

enum JarvisDiagnosticsError: LocalizedError {
    case archiveFailed(Int32)

    var errorDescription: String? {
        switch self {
        case let .archiveFailed(status):
            "诊断日志打包失败（退出码 \(status)）"
        }
    }
}

enum JarvisDiagnosticsExporter {
    static func exportArchive(
        clipboardItems: [ClipboardItem]? = nil,
        cacheStore: ClipboardCacheStore? = nil,
        autoCleanupEnabled: Bool? = nil,
        outputURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("JarvisDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stagingDirectory.path)

        defer {
            try? fileManager.removeItem(at: stagingDirectory)
        }

        // 日志写入是异步批量的，先落盘再打包，否则最近几百毫秒的事件会漏掉。
        JarvisLog.flush()
        let eventFiles = JarvisLog.eventFileURLs
        for sourceURL in eventFiles {
            let destinationURL = stagingDirectory.appendingPathComponent(
                sourceURL.lastPathComponent,
                isDirectory: false
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        }

        let updateLogURL = JarvisUpdateService.updateLogURL
        if fileManager.fileExists(atPath: updateLogURL.path),
           let updateLog = try? String(contentsOf: updateLogURL, encoding: .utf8)
        {
            let safeUpdateLog = updateLog
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { JarvisLogRedactor.text(String($0)) }
                .joined(separator: "\n")
            let destinationURL = stagingDirectory.appendingPathComponent("update.log", isDirectory: false)
            try Data(safeUpdateLog.utf8).write(to: destinationURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
        }

        let audit: ClipboardCacheAudit? = if let clipboardItems, let cacheStore {
            cacheStore.audit(items: clipboardItems)
        } else {
            nil
        }
        let manifest = JarvisDiagnosticsManifest(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            appVersion: JarvisAppVersion.shortVersion,
            build: JarvisAppVersion.build,
            bundleID: JarvisAppIdentity.bundleIdentifier,
            bundlePath: JarvisLogRedactor.path(Bundle.main.bundleURL.path),
            processID: ProcessInfo.processInfo.processIdentifier,
            sessionID: JarvisLog.sessionID,
            includesClipboardContent: false,
            logFileNames: eventFiles.map(\.lastPathComponent),
            cacheAutoCleanupEnabled: autoCleanupEnabled,
            cacheAudit: audit
        )
        let manifestURL = stagingDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        let manifestData = try JSONEncoder().encode(manifest)
        try JarvisProtectedStorage.write(manifestData, to: manifestURL)

        let archiveURL = outputURL
            ?? fileManager.temporaryDirectory.appendingPathComponent(
                "Jarvis-diagnostics-\(UUID().uuidString).zip",
                isDirectory: false
            )
        try? fileManager.removeItem(at: archiveURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", stagingDirectory.path, archiveURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw JarvisDiagnosticsError.archiveFailed(process.terminationStatus)
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        JarvisLog.info(
            category: .storage,
            event: "diagnostics.export.complete",
            result: "success",
            fields: [
                "logFileCount": String(eventFiles.count),
                "includesClipboardContent": "false"
            ]
        )
        return archiveURL
    }
}
