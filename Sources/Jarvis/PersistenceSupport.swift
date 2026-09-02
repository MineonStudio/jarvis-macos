import Foundation
import OSLog

enum JarvisPersistenceLog {
    static let logger = Logger(subsystem: JarvisAppIdentity.bundleIdentifier, category: "persistence")
}

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
