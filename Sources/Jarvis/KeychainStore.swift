import Foundation
import OSLog
import Security

enum KeychainStoreError: LocalizedError {
    case updateFailed(OSStatus)
    case addFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .updateFailed(status):
            "更新钥匙串项目失败（状态码 \(status)）"
        case let .addFailed(status):
            "写入钥匙串项目失败（状态码 \(status)）"
        case let .deleteFailed(status):
            "删除钥匙串项目失败（状态码 \(status)）"
        }
    }
}

final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.jarvis.mac"
    private let logger = Logger(subsystem: "com.jarvis.mac", category: "keychain")

    func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setValue(_ value: String, for account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("SecItemAdd failed: \(addStatus, privacy: .public)")
                throw KeychainStoreError.addFailed(addStatus)
            }
        default:
            logger.error("SecItemUpdate failed: \(status, privacy: .public)")
            throw KeychainStoreError.updateFailed(status)
        }
    }

    func deleteValue(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("SecItemDelete failed: \(status, privacy: .public)")
            throw KeychainStoreError.deleteFailed(status)
        }
    }
}
