import Foundation
import CryptoKit
import Security

/// Re-signs an installed copy with a certificate that lives on this Mac.
///
/// Shipping builds are ad-hoc signed, so every replacement is a new code
/// identity and macOS drops the Screen Recording, Accessibility, Microphone,
/// Camera, and Keychain
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
    /// camera access. Defined once in `JarvisSigningScript` so the shell paths
    /// cannot drift away from this one.
    static var entitlements: String {
        JarvisSigningScript.entitlements
    }

    /// Whether this Mac carries the identity `install.sh` creates.
    static var isAvailable: Bool {
        isIdentityInstalled(identityName)
    }

    /// Whether an app is signed by the certificate in this user's keychain.
    /// A matching display name alone is not enough: an ad-hoc copy and a
    /// self-signed copy can coexist on the same Mac, and TCC treats them as
    /// different applications.
    static func isSignedWithInstalledIdentity(appAt appURL: URL) -> Bool {
        guard let appFingerprint = signingCertificateFingerprint(appAt: appURL),
              let fingerprints = installedIdentityFingerprints(identityName)
        else { return false }
        return fingerprints.contains(appFingerprint)
    }

    static func signingCertificateFingerprint(appAt appURL: URL) -> String? {
        guard let requirement = signingRequirement(of: appURL) else { return nil }
        return signingCertificateFingerprint(from: requirement)
    }

    /// Hashes the designated requirement so ad-hoc updates (whose requirement
    /// contains a cdhash) and certificate-signed updates can both be compared.
    static func codeIdentityFingerprint(appAt appURL: URL) -> String? {
        guard let requirement = signingRequirement(of: appURL) else { return nil }
        let digest = SHA256.hash(data: Data(requirement.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func signingCertificateFingerprint(from requirement: String) -> String? {
        guard let marker = requirement.range(of: "certificate root = H\""),
              let end = requirement[marker.upperBound...].firstIndex(of: "\"")
        else {
            return nil
        }
        return String(requirement[marker.upperBound ..< end]).lowercased()
    }

    /// Reuse the current app's exact certificate when possible. If this is an
    /// identity transition, choose a stable certificate hash rather than a
    /// potentially ambiguous common name.
    static func localSigningFingerprint(matching currentFingerprint: String? = nil) -> String? {
        guard let fingerprints = installedIdentityFingerprints(identityName) else { return nil }
        if let currentFingerprint, fingerprints.contains(currentFingerprint) {
            return currentFingerprint
        }
        return fingerprints.sorted().first
    }

    private static func signingRequirement(of appURL: URL) -> String? {
        runCapturingError(
            executable: "/usr/bin/codesign",
            arguments: ["-d", "-r-", appURL.path]
        )
    }

    private static func installedIdentityFingerprints(_ name: String) -> Set<String>? {
        guard let output = run(
            executable: "/usr/bin/security",
            arguments: [
                "find-certificate", "-Z", "-c", name,
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Keychains/login.keychain-db"
            ]
        ) else {
            return nil
        }
        let hashes = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.hasPrefix("SHA-1 hash:") else { return nil }
                return line
                    .split(separator: ":", maxSplits: 1)
                    .last?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }
        return hashes.isEmpty ? nil : Set(hashes)
    }

    /// Keychain only lists a self-signed certificate under the plain
    /// code-signing policy, never under "valid identities", so do not pass
    /// `-v` here.
    static func isIdentityInstalled(_ name: String) -> Bool {
        guard let output = run(
            executable: "/usr/bin/security",
            arguments: [
                "find-identity", "-p", "codesigning",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Keychains/login.keychain-db"
            ]
        ) else {
            return false
        }
        return output.localizedCaseInsensitiveContains(name)
    }

    /// Signs `appURL` with the local identity. Callers must not fall back to
    /// ad-hoc signing because that would change the TCC code identity.
    static func resign(appAt appURL: URL, identity: String = identityName) throws {
        guard isIdentityInstalled(identity) else {
            throw JarvisUpdateError.localSigningFailed(
                "登录钥匙串中找不到证书指纹 \(identity.uppercased())。请解锁登录钥匙串后重试"
            )
        }

        let fileManager = FileManager.default
        let entitlementsURL = fileManager.temporaryDirectory
            .appendingPathComponent("Jarvis-entitlements-\(UUID().uuidString).plist")
        try Data(entitlements.utf8).write(to: entitlementsURL, options: .atomic)
        defer { try? fileManager.removeItem(at: entitlementsURL) }

        try runOrThrow(
            executable: "/usr/bin/codesign",
            arguments: [
                "--keychain",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Keychains/login.keychain-db",
                "--force",
                "--options", "runtime",
                "--entitlements", entitlementsURL.path,
                "--sign", identity.count == 40 ? identity.uppercased() : identity,
                appURL.path
            ]
        )
    }

    // MARK: - Adopting an identity on a Mac that installed from a zip

    /// Whether this installation could take on a local identity right now.
    ///
    /// Every release ships ad-hoc signed, so a Mac that installed by dragging
    /// the app out of the zip starts out with no certificate at all; that is
    /// the case this exists for. Adopting means re-signing the bundle, which
    /// must happen before permission grants so every later same-channel update
    /// can keep using this identity.
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
        return !isSignedWithInstalledIdentity(appAt: appURL)
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

    /// 上一次本机签名失败的原因落在哪。
    ///
    /// 签名是应用退出之后才由脚本做的，失败时脚本会把应用重新打开，可那一刻已经
    /// 没有进程能报告错误了。原因因此写到磁盘上，由下一次启动认领一次。
    static var failureReportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Jarvis/adopt-failure.txt")
    }

    /// 读取并清掉上一次的失败原因；没有就返回 nil。
    static func consumeAdoptionFailure() -> String? {
        guard let message = try? String(contentsOf: failureReportURL, encoding: .utf8) else {
            return nil
        }
        try? FileManager.default.removeItem(at: failureReportURL)
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 内嵌脚本对外可见，只为了让测试能拿它跟 `install.sh` 比对并做语法检查。
    static func adoptionScript(
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

        # 应用是用户点了按钮之后才退出的：任何一步失败都得把它放回来，否则贾维斯
        # 就是凭空消失，而且没有任何东西告诉用户发生了什么。
        fail() {
            log "$1"
            /bin/mkdir -p "$(/usr/bin/dirname "$failure_report")" 2>/dev/null || true
            print -r -- "$1" > "$failure_report" 2>/dev/null || true
            /usr/bin/open "$app" >/dev/null 2>&1 || true
            exit 1
        }

        app=\(shellQuote(appURL.path))
        failure_report=\(shellQuote(failureReportURL.path))
        identity=\(shellQuote(identityName))
        bundle_id=\(shellQuote(bundleIdentifier))
        work=\(shellQuote(workDirectory.path))
        login_keychain=\(JarvisSigningScript.loginKeychain)
        parent_pid=\(parentProcessID)

        log "等待应用退出"
        \(JarvisSigningScript.waitForParentExit)

        \(JarvisSigningScript.ensureIdentity)

        \(JarvisSigningScript.trustIdentity)

        \(JarvisSigningScript.resetPrivacyPermissions)

        log "在副本上签名"
        /usr/bin/ditto "$app" "$work/Signed.app" || fail "复制失败"
        target="$work/Signed.app"
        entitlements="$work/entitlements.plist"
        \(JarvisSigningScript.signAndVerify)

        log "替换应用"
        /bin/mv "$app" "$work/Replaced.app" || fail "移开旧应用失败"
        if ! /usr/bin/ditto "$work/Signed.app" "$app"; then
            log "写入新应用失败，回滚"
            /bin/mv "$work/Replaced.app" "$app"
            fail "写入新应用失败，已回滚到原版本"
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

    private static func runCapturingError(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = outputPipe

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
            throw JarvisUpdateError.signingToolFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            let message = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw JarvisUpdateError.signingToolFailed(
                message?.isEmpty == false ? message! : "codesign 返回状态码 \(process.terminationStatus)"
            )
        }
    }
}
