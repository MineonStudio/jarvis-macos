import Foundation
import Security

/// 仅用于升级时读取并清理旧版本保存的钥匙串项目；新配置不会再写入钥匙串。
enum JarvisLegacyKeychainMigration {
    static func loadOrMigrate(
        file: JarvisJSONFile<String>,
        markerKey: String,
        legacyServices: [String]
    ) throws -> String? {
        let defaults = UserDefaults.standard
        let localValue = try file.readForWriting(default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !localValue.isEmpty {
            if !defaults.bool(forKey: markerKey) {
                defaults.set(true, forKey: markerKey)
                deleteLegacyItems(services: legacyServices)
            }
            return localValue
        }

        guard !defaults.bool(forKey: markerKey) else { return nil }

        for service in legacyServices {
            guard let value = try read(service: service),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }

            try file.writeOrThrow(value)
            defaults.set(true, forKey: markerKey)
            deleteLegacyItems(services: legacyServices)
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        defaults.set(true, forKey: markerKey)
        return nil
    }

    static func deleteLegacyItems(services: [String]) {
        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "api-key"
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func read(service: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw LegacyKeychainReadError(status: status)
        }
        return value
    }
}

private struct LegacyKeychainReadError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "旧配置迁移失败（\(status)）"
    }
}
