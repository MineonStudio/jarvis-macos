import XCTest
@testable import Jarvis

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

    func testScreenRecordingPermissionResetCommandUsesBundleIdentity() {
        XCTAssertEqual(
            JarvisUpdateService.screenRecordingPermissionResetArguments(
                bundleIdentifier: "com.jarvis.mac"
            ),
            ["reset", "ScreenCapture", "com.jarvis.mac"]
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
