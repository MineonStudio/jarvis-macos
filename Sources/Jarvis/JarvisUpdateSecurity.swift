import CryptoKit
import Foundation

struct JarvisUpdateManifest: Codable, Equatable {
    let schemaVersion: Int
    let version: String
    let build: String
    let bundleIdentifier: String
    let channel: String
    let archiveName: String
    let sha256: String
}

enum JarvisUpdateSecurity {
    static let maximumManifestBytes = 64 * 1024
    static let maximumSignatureBytes = 1024
    static let maximumArchiveBytes: Int64 = 2 * 1024 * 1024 * 1024

    static func verifyManifest(
        data: Data,
        signatureData: Data,
        publicKeyBase64: String
    ) throws -> JarvisUpdateManifest {
        guard data.count <= maximumManifestBytes,
              let signatureText = String(data: signatureData, encoding: .utf8),
              signatureText.utf8.count <= maximumSignatureBytes,
              let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64,
              let keyData = Data(base64Encoded: publicKeyBase64),
              keyData.count == 32
        else {
            throw JarvisUpdateError.invalidManifestSignature
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard publicKey.isValidSignature(signature, for: data) else {
            throw JarvisUpdateError.invalidManifestSignature
        }

        let manifest = try JSONDecoder().decode(JarvisUpdateManifest.self, from: data)
        guard manifest.schemaVersion == 1,
              manifest.channel == "stable",
              isValidVersion(manifest.version),
              Int(manifest.build) != nil,
              (Int(manifest.build) ?? 0) > 0,
              manifest.build.count <= 32,
              manifest.bundleIdentifier == "com.jarvis.mac",
              manifest.archiveName == "Jarvis-update.zip",
              isValidSHA256(manifest.sha256)
        else {
            throw JarvisUpdateError.invalidManifest
        }
        return manifest
    }

    static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    static func isValidVersion(_ value: String) -> Bool {
        guard let normalized = normalizedVersion(value) else { return false }
        let components = normalized.split(separator: ".")
        return components.count == 3 && components.allSatisfy { Int($0) != nil }
    }

    static func normalizedVersion(_ value: String) -> String? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }
        guard !normalized.isEmpty,
              normalized.allSatisfy({ $0.isNumber || $0 == "." }),
              !normalized.hasPrefix("."),
              !normalized.hasSuffix(".")
        else {
            return nil
        }
        return normalized
    }

    static func numericParts(_ value: String) -> [Int]? {
        guard let normalized = normalizedVersion(value) else { return nil }
        let parts = normalized.split(separator: ".")
        guard (1 ... 3).contains(parts.count) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        return values
    }

    static func isNewer(
        remoteVersion: String,
        remoteBuild: String?,
        than localVersion: String,
        localBuild: String?
    ) -> Bool {
        guard let remoteParts = numericParts(remoteVersion),
              let localParts = numericParts(localVersion)
        else {
            return false
        }

        for index in 0 ..< max(remoteParts.count, localParts.count) {
            let remote = index < remoteParts.count ? remoteParts[index] : 0
            let local = index < localParts.count ? localParts[index] : 0
            if remote != local {
                return remote > local
            }
        }

        guard let remoteBuild, let localBuild,
              let remoteBuildNumber = Int(remoteBuild),
              let localBuildNumber = Int(localBuild)
        else {
            return false
        }
        return remoteBuildNumber > localBuildNumber
    }
}

struct JarvisStagedUpdate: Equatable {
    let version: String
    let temporaryDirectoryURL: URL
    let scriptURL: URL
}

enum JarvisInstallSource {
    private static let defaultsKey = "jarvis.install.source"
    private static let knownSources: Set<String> = ["direct-download", "dmg", "development"]

    static func recordIfMissing(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        guard defaults.object(forKey: defaultsKey) == nil else { return }
        let source = bundle.object(forInfoDictionaryKey: "JarvisInstallSource") as? String
        defaults.set(source.flatMap { knownSources.contains($0) ? $0 : nil } ?? "unknown", forKey: defaultsKey)
    }

    static func current(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: defaultsKey) ?? "unknown"
    }
}
