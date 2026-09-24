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

    func readIfAvailable() -> String {
        (try? read()) ?? ""
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
