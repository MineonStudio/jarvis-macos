import OSLog

enum JarvisPersistenceLog {
    static let logger = Logger(subsystem: JarvisAppIdentity.bundleIdentifier, category: "persistence")
}
