import Foundation
import Security

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

    // MARK: - Adopting an identity on a Mac that installed from a zip

    /// Whether this installation could take on a local identity right now.
    ///
    /// Every release ships ad-hoc signed, so a Mac that installed by dragging
    /// the app out of the zip starts out with no certificate at all; that is
    /// the case this exists for. Adopting means re-signing the bundle, which
    /// costs the current grants once and keeps every later update from asking
    /// again.
    static var canAdoptLocalIdentity: Bool {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension.lowercased() == "app",
              !appURL.path.localizedCaseInsensitiveContains("/AppTranslocation/")
        else {
            return false
        }
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            return false
        }
        return certificateCount(of: appURL) == 0
    }

    /// Certificates attached to a bundle's signature; none means ad-hoc.
    /// Team identifier is not usable here — a self-signed certificate has no
    /// team either.
    static func certificateCount(of appURL: URL) -> Int {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return 0
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let information = information as? [String: Any]
        else {
            return 0
        }
        return (information[kSecCodeInfoCertificates as String] as? [Any])?.count ?? 0
    }

    /// Hands the re-signing to a detached script that waits for this process
    /// to exit, so the caller is expected to terminate afterwards.
    ///
    /// The bundle is signed as a copy and swapped in, so a failure part way
    /// through leaves the installation that is running now untouched.
    static func adoptLocalIdentity() throws {
        let appURL = Bundle.main.bundleURL
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.jarvis.mac"

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JarvisAdopt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: workDirectory.path
        )

        try Data(entitlements.utf8).write(
            to: workDirectory.appendingPathComponent("entitlements.plist"),
            options: .atomic
        )

        let scriptURL = workDirectory.appendingPathComponent("adopt-identity.zsh")
        try Data(adoptionScript(
            appURL: appURL,
            bundleIdentifier: bundleIdentifier,
            workDirectory: workDirectory,
            parentProcessID: ProcessInfo.processInfo.processIdentifier
        ).utf8).write(to: scriptURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/zsh", scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func adoptionScript(
        appURL: URL,
        bundleIdentifier: String,
        workDirectory: URL,
        parentProcessID: Int32
    ) -> String {
        """
        #!/bin/zsh
        set -u
        log_file=\(shellQuote(workDirectory.appendingPathComponent("adopt.log").path))
        exec >> "$log_file" 2>&1
        log() {
            echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*"
        }

        app=\(shellQuote(appURL.path))
        identity=\(shellQuote(identityName))
        bundle_id=\(shellQuote(bundleIdentifier))
        work=\(shellQuote(workDirectory.path))
        parent_pid=\(parentProcessID)

        log "等待应用退出"
        while /bin/kill -0 "$parent_pid" 2>/dev/null; do
            /bin/sleep 0.3
        done

        if ! /usr/bin/security find-identity -p codesigning 2>/dev/null | /usr/bin/grep -qF "$identity"; then
            log "生成本机签名证书"
            /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \\
                -keyout "$work/key.pem" -out "$work/cert.pem" \\
                -subj "/CN=$identity/O=Jarvis Local" \\
                -addext "basicConstraints=critical,CA:false" \\
                -addext "keyUsage=critical,digitalSignature" \\
                -addext "extendedKeyUsage=critical,codeSigning" || { log "生成证书失败"; exit 1; }
            /usr/bin/security import "$work/cert.pem" -k "$HOME/Library/Keychains/login.keychain-db" \\
                -T /usr/bin/codesign || { log "导入证书失败"; exit 1; }
            /usr/bin/security import "$work/key.pem" -k "$HOME/Library/Keychains/login.keychain-db" \\
                -T /usr/bin/codesign -T /usr/bin/security || { log "导入私钥失败"; exit 1; }
        fi

        if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -qF "$identity"; then
            log "把证书加入信任设置"
            /usr/bin/security find-certificate -c "$identity" -p \\
                "$HOME/Library/Keychains/login.keychain-db" > "$work/identity.crt" || { log "导出证书失败"; exit 1; }
            /usr/bin/security add-trusted-cert -r trustRoot -p codeSign \\
                -k "$HOME/Library/Keychains/login.keychain-db" "$work/identity.crt" >/dev/null 2>&1 \\
                || log "写入信任设置失败，继续签名"
        fi

        # The old entries belong to the ad-hoc signature and would otherwise
        # stay listed in System Settings as grants for an app that no longer
        # exists.
        /usr/bin/tccutil reset ScreenCapture "$bundle_id" >/dev/null 2>&1
        /usr/bin/tccutil reset Accessibility "$bundle_id" >/dev/null 2>&1

        log "在副本上签名"
        /usr/bin/ditto "$app" "$work/Signed.app" || { log "复制失败"; exit 1; }
        /usr/bin/codesign --force --options runtime --entitlements "$work/entitlements.plist" \\
            --sign "$identity" "$work/Signed.app" || { log "签名失败"; exit 1; }
        /usr/bin/codesign --verify --deep --strict "$work/Signed.app" || { log "签名校验失败"; exit 1; }

        log "替换应用"
        /bin/mv "$app" "$work/Replaced.app" || { log "移开旧应用失败"; exit 1; }
        if ! /usr/bin/ditto "$work/Signed.app" "$app"; then
            log "写入新应用失败，回滚"
            /bin/mv "$work/Replaced.app" "$app"
            exit 1
        fi

        /bin/rm -rf "$work/Replaced.app" "$work/Signed.app" "$work/key.pem" "$work/cert.pem"

        log "重新启动"
        /usr/bin/open "$app"
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
