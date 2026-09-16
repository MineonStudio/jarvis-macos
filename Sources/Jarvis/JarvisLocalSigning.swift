import Foundation

/// Re-signs an installed copy with a certificate that lives on this Mac.
///
/// Shipping builds are ad-hoc signed, so every replacement is a new code
/// identity and macOS drops the Screen Recording, Accessibility, and Keychain
/// grants along with it. `install.sh` installs a self-signed local identity
/// instead; signing each update with that same certificate keeps the identity
/// — and therefore the grants — stable, which is why the update flow skips its
/// TCC reset when this identity is present.
///
/// The certificate is a plain code-signing certificate in the login keychain,
/// not an Apple-issued one, so it never leaves the machine and nothing about
/// it is trusted beyond it.
enum JarvisLocalSigning {
    static let identityName = "Jarvis Local Signing"

    /// Re-signing replaces the whole signature, so the entitlements have to be
    /// passed back in; dropping them would silently cost the microphone and
    /// camera access. Kept in sync with `Resources/Jarvis.entitlements`.
    static let entitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>com.apple.security.cs.allow-jit</key>
    \t<true/>
    \t<key>com.apple.security.device.audio-input</key>
    \t<true/>
    \t<key>com.apple.security.device.camera</key>
    \t<true/>
    </dict>
    </plist>
    """

    /// Whether this Mac carries the identity `install.sh` creates.
    static var isAvailable: Bool {
        isIdentityInstalled(identityName)
    }

    /// Keychain only lists a self-signed certificate under the plain
    /// code-signing policy, never under "valid identities", so do not pass
    /// `-v` here.
    static func isIdentityInstalled(_ name: String) -> Bool {
        guard let output = run(
            executable: "/usr/bin/security",
            arguments: ["find-identity", "-p", "codesigning"]
        ) else {
            return false
        }
        return output.contains(name)
    }

    /// Signs `appURL` with the local identity. Returns `false` without throwing
    /// when the Mac has no such identity, so callers can keep using the ad-hoc
    /// path.
    @discardableResult
    static func resign(appAt appURL: URL, identity: String = identityName) throws -> Bool {
        guard isIdentityInstalled(identity) else { return false }

        let fileManager = FileManager.default
        let entitlementsURL = fileManager.temporaryDirectory
            .appendingPathComponent("Jarvis-entitlements-\(UUID().uuidString).plist")
        try Data(entitlements.utf8).write(to: entitlementsURL, options: .atomic)
        defer { try? fileManager.removeItem(at: entitlementsURL) }

        try runOrThrow(
            executable: "/usr/bin/codesign",
            arguments: [
                "--force",
                "--options", "runtime",
                "--entitlements", entitlementsURL.path,
                "--sign", identity,
                appURL.path
            ]
        )
        return true
    }

    private static func run(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )
    }

    private static func runOrThrow(executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw JarvisUpdateError.toolFailed("签名失败：\(error.localizedDescription)")
        }

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw JarvisUpdateError.toolFailed(
                "签名失败：\(message?.isEmpty == false ? message! : "codesign 返回状态码 \(process.terminationStatus)")"
            )
        }
    }
}
