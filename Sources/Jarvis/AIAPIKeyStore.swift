import Foundation

/// 大模型 API Key 使用与壁纸源相同的应用本地受限权限存储，不写入钥匙串。
final class AIAPIKeyStore: @unchecked Sendable {
    static let shared = AIAPIKeyStore()

    private static let migrationMarker = "jarvis.ai.api-key.local-migration.v1"
    private let file: JarvisJSONFile<String>
    private let legacyServices: [String]

    private init() {
        let bundleIdentifier = JarvisAppIdentity.bundleIdentifier
        legacyServices = [
            "\(bundleIdentifier).ai",
            "\(bundleIdentifier).screenshot-translation"
        ]
        file = JarvisJSONFile(
            directoryURL: JarvisAppDirectory.url("Cache"),
            fileName: "ai-api-key.json",
            logDomain: "ai.api-key"
        )
    }

    /// 返回 "" 有两种情况：没配过 Key（正常），或读失败（异常）。
    /// #22：读失败不能再被 try? 吞成"没配"——记 error 日志，调用方看到""
    /// 时至少能从日志里知道是读坏了而不是用户没填。
    func readIfAvailable() -> String {
        do {
            return try read() ?? ""
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "ai.api-key.read.failed",
                error: error
            )
            return ""
        }
    }

    func read() throws -> String? {
        try JarvisLegacyKeychainMigration.loadOrMigrate(
            file: file,
            markerKey: Self.migrationMarker,
            legacyServices: legacyServices
        )
    }

    func write(_ value: String) throws {
        try file.writeOrThrow(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func delete() throws {
        try file.writeOrThrow("")
        UserDefaults.standard.set(true, forKey: Self.migrationMarker)
        JarvisLegacyKeychainMigration.deleteLegacyItems(services: legacyServices)
    }
}
