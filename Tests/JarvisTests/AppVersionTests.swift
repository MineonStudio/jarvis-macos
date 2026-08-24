@testable import Jarvis
import XCTest

final class AppVersionTests: XCTestCase {
    private let service = JarvisUpdateService()

    func testVersionComparisonIgnoresLeadingVAndComparesNumericParts() {
        XCTAssertTrue(service.isNewer("v0.4.7", than: "0.4.6"))
        XCTAssertTrue(service.isNewer("1.0.0", than: "0.99.99"))
        XCTAssertFalse(service.isNewer("v0.4.6", than: "0.4.6"))
        XCTAssertFalse(service.isNewer("0.4.5", than: "0.4.6"))
    }

    func testVersionDisplayIncludesShortVersionAndBuild() {
        XCTAssertTrue(JarvisAppVersion.displayName.contains(JarvisAppVersion.shortVersion))
        XCTAssertTrue(JarvisAppVersion.displayName.contains(JarvisAppVersion.build))
    }

    func testUpdateLogUsesUserLibraryLogsDirectory() {
        XCTAssertTrue(JarvisUpdateService.updateLogURL.path.hasSuffix("Library/Logs/Jarvis/update.log"))
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
    }

    func testPrivacyPermissionResetTreatsMissingBundleAsAlreadyClean() {
        XCTAssertTrue(
            JarvisPrivacyPermissionReset.isMissingBundleFailure(
                "tccutil: No such bundle identifier \"com.example.app\": OSStatus error -10814"
            )
        )
        XCTAssertFalse(JarvisPrivacyPermissionReset.isMissingBundleFailure("权限服务不可用"))
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

    func testLaunchServicesCleanupKeepsCurrentAppAndTargetsJarvisResidueOnly() {
        let dump = """
        bundle id:                  Jarvis (0x1)
        path:                       /Users/wesley/Downloads/Jarvis.app (0x2)
        identifier:                 com.jarvis.mac
        --------------------------------------------------------------------------------
        bundle id:                  Jarvis Dev (0x3)
        path:                       /Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis-Dev.app (0x4)
        identifier:                 com.jarvis.mac.dev
        --------------------------------------------------------------------------------
        bundle id:                  JarvisStatusBarProbe (0x5)
        path:                       /private/tmp/JarvisStatusBarProbe.app (0x6)
        identifier:                 com.example.jarvis-status-probe
        --------------------------------------------------------------------------------
        bundle id:                  ChatGPT (0x7)
        path:                       /Applications/ChatGPT.app (0x8)
        identifier:                 com.openai.codex
        """

        XCTAssertEqual(
            JarvisUpdateService.launchServicesCleanupPaths(
                from: dump,
                preserving: URL(fileURLWithPath: "/Users/wesley/Downloads/Jarvis.app"),
                bundleIdentifier: "com.jarvis.mac"
            ),
            [
                URL(fileURLWithPath: "/Users/wesley/VibeCodingProjects/贾维斯/dist/Jarvis-Dev.app"),
                URL(fileURLWithPath: "/tmp/JarvisStatusBarProbe.app").standardizedFileURL
            ]
        )
    }

    func testInstallerDoesNotOwnScreenRecordingPermissionReset() throws {
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
        XCTAssertFalse(script.contains("tccutil"))
        XCTAssertFalse(script.contains("reset_screen_recording_permission"))
        XCTAssertTrue(script.contains("refresh_launch_services"))
        XCTAssertTrue(script.contains("lsregister"))
    }
}
