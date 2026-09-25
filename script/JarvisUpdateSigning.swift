import CryptoKit
import Foundation
import Security

private enum JarvisUpdateSigningTool {
    private static let service = "com.jarvis.mac.update-signing.v1"
    private static let account = "release-ed25519"

    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw usageError
        }

        switch command {
        case "generate":
            let key = try loadOrCreatePrivateKey()
            print(key.publicKey.rawRepresentation.base64EncodedString())
        case "public-key":
            let key = try loadPrivateKey()
            print(key.publicKey.rawRepresentation.base64EncodedString())
        case "sign-manifest":
            guard arguments.count == 7 else { throw usageError }
            try signManifest(
                version: arguments[1],
                build: arguments[2],
                bundleIdentifier: arguments[3],
                archiveURL: URL(fileURLWithPath: arguments[4]),
                manifestURL: URL(fileURLWithPath: arguments[5]),
                signatureURL: URL(fileURLWithPath: arguments[6])
            )
        default:
            throw usageError
        }
    }

    private static var usageError: NSError {
        NSError(
            domain: "JarvisUpdateSigningTool",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "用法：generate | public-key | sign-manifest <version> <build> <bundle-id> <archive.zip> <manifest.json> <manifest.sig>"]
        )
    }

    private static func loadOrCreatePrivateKey() throws -> Curve25519.Signing.PrivateKey {
        if let existing = try? loadPrivateKey() { return existing }
        let key = Curve25519.Signing.PrivateKey()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Jarvis update signing key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key.rawRepresentation
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw securityError(status)
        }
        return try loadPrivateKey()
    }

    private static func loadPrivateKey() throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data
        else {
            throw securityError(status)
        }
        return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
    }

    private struct Manifest: Encodable {
        let schemaVersion = 1
        let version: String
        let build: String
        let bundleIdentifier: String
        let channel = "stable"
        let archiveName: String
        let sha256: String
    }

    private static func signManifest(
        version: String,
        build: String,
        bundleIdentifier: String,
        archiveURL: URL,
        manifestURL: URL,
        signatureURL: URL
    ) throws {
        let archiveHandle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? archiveHandle.close() }
        var archiveHasher = SHA256()
        while let chunk = try archiveHandle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            archiveHasher.update(data: chunk)
        }
        let digest = archiveHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        let manifest = Manifest(
            version: version,
            build: build,
            bundleIdentifier: bundleIdentifier,
            archiveName: archiveURL.lastPathComponent,
            sha256: digest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        let privateKey = try loadPrivateKey()
        try verifyEmbeddedPublicKey(matches: privateKey.publicKey)
        let signature = try privateKey.signature(for: manifestData)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try manifestData.write(to: manifestURL, options: .atomic)
        try Data(signature.base64EncodedString().utf8).write(to: signatureURL, options: .atomic)
    }

    private static func verifyEmbeddedPublicKey(matches publicKey: Curve25519.Signing.PublicKey) throws {
        let scriptURL = URL(
            fileURLWithPath: #filePath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
        let infoURL = scriptURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")
        let infoData = try Data(contentsOf: infoURL)
        guard let plist = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let embeddedKey = plist["JarvisUpdatePublicKey"] as? String,
              Data(base64Encoded: embeddedKey) == publicKey.rawRepresentation
        else {
            throw NSError(
                domain: "JarvisUpdateSigningTool",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "钥匙串私钥与应用内置公钥不匹配；拒绝签署更新清单"]
            )
        }
    }

    private static func securityError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "钥匙串操作失败"]
        )
    }
}

do {
    try JarvisUpdateSigningTool.main()
} catch {
    fputs("Jarvis update signer: \(error.localizedDescription)\n", stderr)
    exit(1)
}
