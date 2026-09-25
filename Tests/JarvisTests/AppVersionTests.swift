import CryptoKit
@testable import Jarvis
import XCTest

final class AppVersionTests: XCTestCase {
    private let service = JarvisUpdateService()

    private func assertZshSyntax(of scriptURL: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n", scriptURL.path]
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let message = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "Installer zsh syntax error: \(message)", file: file, line: line)
    }

    func testVersionComparisonIgnoresLeadingVAndComparesNumericParts() {
        XCTAssertTrue(service.isNewer("v0.4.7", than: "0.4.6"))
        XCTAssertTrue(service.isNewer("1.0.0", than: "0.99.99"))
        XCTAssertFalse(service.isNewer("v0.4.6", than: "0.4.6"))
        XCTAssertFalse(service.isNewer("0.4.5", than: "0.4.6"))
    }

    func testBuildNumberBreaksTiesForTheSameMarketingVersion() throws {
        let release = try JarvisReleaseInfo(
            version: "1.4.5",
            build: "344",
            releaseURL: XCTUnwrap(URL(string: "https://github.com/MineonStudio/jarvis-macos/releases/tag/v1.4.5")),
            downloadURL: XCTUnwrap(URL(string: "https://github.com/MineonStudio/jarvis-macos/releases/download/v1.4.5/Jarvis-update.zip")),
            assetDigest: "sha256:\(String(repeating: "a", count: 64))",
            archiveSize: 1,
            isLegacyBootstrap: false
        )

        XCTAssertTrue(service.isNewer(release, than: "1.4.5", build: "343"))
        XCTAssertFalse(service.isNewer(release, than: "1.4.5", build: "344"))
    }

    func testLegacyBootstrapIsRestrictedToThePublishedBridgeVersion() {
        XCTAssertTrue(service.isLegacyBootstrapRelease("v1.4.5"))
        XCTAssertFalse(service.isLegacyBootstrapRelease("1.4.4"))
        XCTAssertFalse(service.isLegacyBootstrapRelease("1.4.6"))
    }

    func testSignedUpdateManifestRequiresValidSignatureAndFields() throws {
        let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 0x42, count: 32))
        let manifest = JarvisUpdateManifest(
            schemaVersion: 1,
            version: "1.4.5",
            build: "344",
            bundleIdentifier: "com.jarvis.mac",
            channel: "stable",
            archiveName: "Jarvis-update.zip",
            sha256: String(repeating: "a", count: 64)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        let signature = try privateKey.signature(for: manifestData)
        let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()

        XCTAssertEqual(
            try JarvisUpdateSecurity.verifyManifest(
                data: manifestData,
                signatureData: Data(signature.base64EncodedString().utf8),
                publicKeyBase64: publicKey
            ),
            manifest
        )

        var tamperedData = manifestData
        tamperedData[tamperedData.startIndex] ^= 1
        XCTAssertThrowsError(
            try JarvisUpdateSecurity.verifyManifest(
                data: tamperedData,
                signatureData: Data(signature.base64EncodedString().utf8),
                publicKeyBase64: publicKey
            )
        )
    }

    func testInstallSourceIsRecordedOnce() throws {
        let suiteName = "JarvisInstallSourceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dmg", forKey: "jarvis.install.source")

        JarvisInstallSource.recordIfMissing(defaults: defaults)

        XCTAssertEqual(JarvisInstallSource.current(defaults: defaults), "dmg")
    }

    func testVersionDisplayIncludesShortVersionAndBuild() {
        XCTAssertTrue(JarvisAppVersion.displayName.contains(JarvisAppVersion.shortVersion))
        XCTAssertTrue(JarvisAppVersion.displayName.contains(JarvisAppVersion.build))
    }

    func testUpdateLogUsesUserLibraryLogsDirectory() {
        XCTAssertTrue(JarvisUpdateService.updateLogURL.path.hasSuffix("Library/Logs/Jarvis/update.log"))
    }

    func testUpdateDigestIsRequiredAndVerified() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-update-digest-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let data = Data("Jarvis 0.9.0".utf8)
        try data.write(to: fileURL)

        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertNoThrow(try service.verifyDigest(of: fileURL, expected: "sha256:\(digest)"))
        XCTAssertThrowsError(try service.verifyDigest(of: fileURL, expected: nil)) { error in
            guard let updateError = error as? JarvisUpdateError,
                  case .checksumUnavailable = updateError
            else {
                return XCTFail("Expected missing digest error, got \(error)")
            }
        }
        XCTAssertThrowsError(try service.verifyDigest(of: fileURL, expected: "sha256:\(String(repeating: "0", count: 64))")) { error in
            guard let updateError = error as? JarvisUpdateError,
                  case .checksumMismatch = updateError
            else {
                return XCTFail("Expected digest mismatch error, got \(error)")
            }
        }
    }

    func testPrivacyPermissionResetCommandsUseBundleIdentity() {
        XCTAssertEqual(
            JarvisUpdateService.privacyPermissionResetArguments(
                bundleIdentifier: "com.jarvis.mac"
            ),
            [
                ["reset", "ScreenCapture", "com.jarvis.mac"],
                ["reset", "Accessibility", "com.jarvis.mac"]
            ]
        )
    }

    func testPrivacyPermissionSettingsUseDirectSystemSettingsAnchors() {
        XCTAssertEqual(JarvisPrivacyPermission.screenCapture.settingsAnchor, "Privacy_ScreenCapture")
        XCTAssertEqual(JarvisPrivacyPermission.accessibility.settingsAnchor, "Privacy_Accessibility")
        XCTAssertEqual(JarvisPrivacyPermission.microphone.settingsAnchor, "Privacy_Microphone")
        XCTAssertEqual(JarvisPrivacyPermission.camera.settingsAnchor, "Privacy_Camera")
    }

    func testRequiredPermissionsCoverScreenAccessibilityMicrophoneAndCamera() {
        XCTAssertEqual(
            JarvisRequiredPermission.allCases.map(\.id),
            ["screenCapture", "accessibility", "microphone", "camera"]
        )
        XCTAssertEqual(JarvisRequiredPermission.screenCapture.title, "屏幕录制")
        XCTAssertEqual(JarvisRequiredPermission.accessibility.privacyPermission, .accessibility)
        XCTAssertEqual(JarvisRequiredPermission.microphone.privacyPermission, .microphone)
        XCTAssertEqual(JarvisRequiredPermission.camera.privacyPermission, .camera)
    }

    func testPrivacyPermissionResetTreatsMissingBundleAsAlreadyClean() {
        XCTAssertTrue(
            JarvisPrivacyPermissionReset.isMissingBundleFailure(
                "tccutil: No such bundle identifier \"com.example.app\": OSStatus error -10814"
            )
        )
        XCTAssertFalse(JarvisPrivacyPermissionReset.isMissingBundleFailure("权限服务不可用"))
    }

    func testLaunchAtLoginPreferenceDefaultsToDisabled() throws {
        let suiteName = "jarvis-launch-at-login-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(JarvisLaunchAtLoginPreference.load(from: defaults))
        XCTAssertEqual(
            defaults.object(forKey: JarvisLaunchAtLoginPreference.key) as? Bool,
            false
        )
    }

    func testLaunchAtLoginPreferencePreservesExplicitChoice() throws {
        let suiteName = "jarvis-launch-at-login-choice-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: JarvisLaunchAtLoginPreference.key)

        XCTAssertFalse(JarvisLaunchAtLoginPreference.load(from: defaults))
    }

    func testFreshInstallPermissionCleanupRunsOncePerInstallationFingerprint() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-fresh-install-test-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = temporaryRoot.appendingPathComponent("Jarvis.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let suiteName = "jarvis-fresh-install-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var resetCount = 0
        let firstRun = try JarvisFreshInstallPermissionCleanup.runIfNeeded(
            bundleURL: bundleURL,
            bundleIdentifier: "com.jarvis.mac",
            defaults: defaults
        ) {
            resetCount += 1
        }
        let secondRun = try JarvisFreshInstallPermissionCleanup.runIfNeeded(
            bundleURL: bundleURL,
            bundleIdentifier: "com.jarvis.mac",
            defaults: defaults
        ) {
            resetCount += 1
        }

        XCTAssertTrue(firstRun)
        XCTAssertFalse(secondRun)
        XCTAssertEqual(resetCount, 1)
    }

    func testPendingIdentityTransitionForcesOnePermissionReset() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-pending-reset-test-\(UUID().uuidString)", isDirectory: true)
        let bundleURL = temporaryRoot.appendingPathComponent("Jarvis.app", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let suiteName = "jarvis-pending-reset-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            JarvisFreshInstallPermissionCleanup.installationFingerprint(for: bundleURL),
            forKey: "jarvis.installation.permission-reset.fingerprint"
        )

        var resetCount = 0
        let didReset = try JarvisFreshInstallPermissionCleanup.runIfNeeded(
            bundleURL: bundleURL,
            bundleIdentifier: "com.jarvis.mac",
            defaults: defaults,
            force: true
        ) {
            resetCount += 1
        }

        XCTAssertTrue(didReset)
        XCTAssertEqual(resetCount, 1)
    }

    func testLaunchServicesCleanupKeepsRunningAndResolvedAppsAndTargetsJarvisResidueOnly() {
        let dump = """
        bundle id:                  Jarvis (0x1)
        path:                       /private/var/folders/vy/AppTranslocation/ABC/d/Jarvis.app (0x2)
        identifier:                 com.jarvis.mac
        --------------------------------------------------------------------------------
        bundle id:                  Jarvis (0x2)
        path:                       /tmp/Jarvis.app (0x3)
        identifier:                 com.jarvis.mac
        --------------------------------------------------------------------------------
        bundle id:                  Jarvis Dev (0x3)
        path:                       /Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis-Dev.app (0x5)
        identifier:                 com.jarvis.mac.dev
        --------------------------------------------------------------------------------
        bundle id:                  JarvisStatusBarProbe (0x5)
        path:                       /private/tmp/JarvisStatusBarProbe.app (0x7)
        identifier:                 com.example.jarvis-status-probe
        --------------------------------------------------------------------------------
        bundle id:                  Jarvis (0x8)
        path:                       /tmp/OldJarvis.app (0x8)
        identifier:                 com.jarvis.mac
        --------------------------------------------------------------------------------
        bundle id:                  ChatGPT (0x7)
        path:                       /Applications/ChatGPT.app (0x9)
        identifier:                 com.openai.codex
        """

        XCTAssertEqual(
            JarvisUpdateService.launchServicesCleanupPaths(
                from: dump,
                preserving: [
                    URL(fileURLWithPath: "/private/var/folders/vy/AppTranslocation/ABC/d/Jarvis.app"),
                    URL(fileURLWithPath: "/tmp/Jarvis.app")
                ],
                bundleIdentifier: "com.jarvis.mac"
            ),
            [
                URL(fileURLWithPath: "/tmp/OldJarvis.app")
            ]
        )
    }

    func testInstallerOnlySchedulesResetWhenSigningIdentityChanges() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-update-test-\(UUID().uuidString).zsh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        try service.makeInstallerScript(
            at: scriptURL,
            currentAppURL: URL(fileURLWithPath: "/Applications/Jarvis.app"),
            newAppURL: URL(fileURLWithPath: "/tmp/Jarvis.app"),
            temporaryDirectory: URL(fileURLWithPath: "/tmp/JarvisUpdate"),
            parentProcessID: 1234
        )
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        try assertZshSyntax(of: scriptURL)
        XCTAssertTrue(script.contains("needs_permission_reset=false"))
        XCTAssertTrue(script.contains("[[ \"$needs_permission_reset\" == \"true\" ]] || return 0"))
        XCTAssertFalse(script.contains("reset_screen_recording_permission"))
        XCTAssertFalse(script.contains("kill -TERM"))
        XCTAssertFalse(script.contains("kill -KILL"))
        XCTAssertTrue(script.contains("refresh_launch_services"))
        XCTAssertTrue(script.contains("lsregister"))
        XCTAssertTrue(script.contains("等待用户已批准退出的应用结束"))
        XCTAssertTrue(script.contains("/bin/rm -rf \"$old_app\""))
        XCTAssertTrue(script.contains("quoted form of oldApp & \" && /bin/mv \" & quoted form of backupApp"))
        if let verifyRange = script.range(of: "codesign --verify"),
           let quarantineRange = script.range(of: "xattr -dr com.apple.quarantine")
        {
            XCTAssertLessThan(verifyRange.lowerBound, quarantineRange.lowerBound)
            XCTAssertLessThan(try XCTUnwrap(script.range(of: "等待用户已批准退出的应用结束")?.lowerBound), verifyRange.lowerBound)
        } else {
            XCTFail("Installer should verify the signature before removing quarantine")
        }
    }

    func testInstallerSchedulesPermissionResetForIdentityTransition() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-update-transition-test-\(UUID().uuidString).zsh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        try service.makeInstallerScript(
            at: scriptURL,
            currentAppURL: URL(fileURLWithPath: "/Applications/Jarvis.app"),
            newAppURL: URL(fileURLWithPath: "/tmp/Jarvis.app"),
            temporaryDirectory: URL(fileURLWithPath: "/tmp/JarvisUpdate"),
            parentProcessID: 1234,
            requiresPermissionReset: true
        )
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        try assertZshSyntax(of: scriptURL)
        XCTAssertTrue(script.contains("needs_permission_reset=true"))
        XCTAssertTrue(script.contains("jarvis.installation.permission-reset.pending -bool true"))
        XCTAssertTrue(script.contains("clear_permission_reset_pending"))
    }
}
