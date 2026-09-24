import Foundation

/// Wallhaven API Key 使用应用本地受限权限文件保存，不写入钥匙串。
final class WallhavenAPIKeyStore: @unchecked Sendable {
    static let shared = WallhavenAPIKeyStore()

    private static let migrationMarker = "jarvis.wallhaven.api-key.local-migration.v1"
    private let file: JarvisJSONFile<String>
    private let legacyServices: [String]

    private init() {
        legacyServices = ["\(JarvisAppIdentity.bundleIdentifier).wallhaven"]
        file = JarvisJSONFile(
            directoryURL: JarvisAppDirectory.url("Cache"),
            fileName: "wallhaven-api-key.json",
            logDomain: "wallhaven.api-key"
        )
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
