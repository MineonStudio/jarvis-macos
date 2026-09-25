@testable import Jarvis
import XCTest

/// 签名与安装流程曾经有三份各自演化的拷贝，漂移的代价是用户静默丢掉权限：
/// entitlements 少一项就是麦克风或摄像头没了，等待退出少一段超时就是应用卡在
/// 中间态。这些断言把三处钉在一起，让漂移在 CI 上失败。
final class JarvisSigningScriptTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repositoryFile(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    /// 去掉缩进与空行后逐行比对：三处的缩进层级不同，但有效内容必须一样。
    private func significantLines(_ text: String) -> [String] {
        text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func assertContains(
        _ fragment: String,
        in text: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let haystack = significantLines(text)
        let needle = significantLines(fragment)
        XCTAssertFalse(needle.isEmpty, "片段本身是空的：\(message)", file: file, line: line)

        let found = haystack.indices.contains { start in
            guard start + needle.count <= haystack.count else { return false }
            return Array(haystack[start ..< start + needle.count]) == needle
        }
        XCTAssertTrue(found, message, file: file, line: line)
    }

    // MARK: - entitlements

    func testLocalSigningFingerprintComesFromTheDesignatedRequirement() {
        XCTAssertEqual(
            JarvisLocalSigning.signingCertificateFingerprint(
                from: #"designated => identifier "com.jarvis.mac" and certificate root = H"597FC147C96E69F52B31BD24795A832004485BF1""#
            ),
            "597fc147c96e69f52b31bd24795a832004485bf1"
        )
        XCTAssertNil(
            JarvisLocalSigning.signingCertificateFingerprint(
                from: #"designated => anchor apple generic and identifier "com.jarvis.mac"#
            )
        )
    }

    /// 重新签名会整体替换签名，漏掉一项就是静默收走一项系统权限。
    func testSigningEntitlementsMatchTheBuiltBundlesCopy() throws {
        let shipped = try repositoryFile("Resources/Jarvis.entitlements")
        XCTAssertEqual(
            significantLines(JarvisSigningScript.entitlements),
            significantLines(shipped),
            "JarvisSigningScript.entitlements 与 Resources/Jarvis.entitlements 已经不一致"
        )
    }

    func testInstallScriptWritesTheSameEntitlements() throws {
        let installScript = try repositoryFile("install.sh")
        assertContains(
            JarvisSigningScript.entitlements,
            in: installScript,
            "install.sh 里的 entitlements 与 JarvisSigningScript 已经不一致"
        )
    }

    // MARK: - 三处共用的 shell 片段

    func testInstallScriptEmbedsEverySharedFragment() throws {
        let installScript = try repositoryFile("install.sh")
        let fragments: [(String, String)] = [
            (JarvisSigningScript.ensureIdentity, "生成证书"),
            (JarvisSigningScript.trustIdentity, "信任设置"),
            (JarvisSigningScript.signAndVerify, "签名与校验")
        ]
        for (fragment, name) in fragments {
            assertContains(
                fragment,
                in: installScript,
                "install.sh 的\(name)片段与 JarvisSigningScript 已经不一致"
            )
        }
    }

    /// adoption 脚本是这台 Mac 上唯一会重签自己的路径，语法错误会直接让用户
    /// 失去应用，所以拿真实的 zsh 解析一遍。
    func testAdoptionScriptIsValidShellAndCarriesTheSharedFragments() throws {
        let script = JarvisLocalSigning.adoptionScript(
            appURL: URL(fileURLWithPath: "/Applications/Jarvis.app"),
            bundleIdentifier: "com.jarvis.mac",
            workDirectory: URL(fileURLWithPath: "/tmp/JarvisAdopt-Test"),
            parentProcessID: 4242
        )

        for fragment in [
            JarvisSigningScript.ensureIdentity,
            JarvisSigningScript.trustIdentity,
            JarvisSigningScript.resetPrivacyPermissions,
            JarvisSigningScript.signAndVerify,
            JarvisSigningScript.waitForParentExit
        ] {
            assertContains(fragment, in: script, "生成的 adoption 脚本缺少共享片段")
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-adopt-syntax-\(UUID().uuidString).zsh")
        defer { try? FileManager.default.removeItem(at: scriptURL) }
        try Data(script.utf8).write(to: scriptURL, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n", scriptURL.path]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let message = String(
            data: errors.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "adoption 脚本语法错误：\(message)")
    }

    /// 共享片段把失败交给调用方的 `fail`，两边都必须提供，否则脚本一遇到错误
    /// 就会以「command not found」告终。
    func testBothCallersDefineTheFailHookTheFragmentsUse() throws {
        let installScript = try repositoryFile("install.sh")
        XCTAssertTrue(installScript.contains("fail() {"), "install.sh 没有定义 fail")

        let adoption = JarvisLocalSigning.adoptionScript(
            appURL: URL(fileURLWithPath: "/Applications/Jarvis.app"),
            bundleIdentifier: "com.jarvis.mac",
            workDirectory: URL(fileURLWithPath: "/tmp/JarvisAdopt-Test"),
            parentProcessID: 4242
        )
        XCTAssertTrue(adoption.contains("fail() {"), "adoption 脚本没有定义 fail")
    }

    /// 应用是用户点了按钮之后才退出的。任何一条失败路径都必须把它放回来，
    /// 否则贾维斯会凭空消失，而且没有任何东西告诉用户发生了什么。
    func testAdoptionScriptRelauchesTheAppOnEveryFailurePath() {
        let script = JarvisLocalSigning.adoptionScript(
            appURL: URL(fileURLWithPath: "/Applications/Jarvis.app"),
            bundleIdentifier: "com.jarvis.mac",
            workDirectory: URL(fileURLWithPath: "/tmp/JarvisAdopt-Test"),
            parentProcessID: 4242
        )

        let failBody = script
            .components(separatedBy: "fail() {")
            .last?
            .components(separatedBy: "}") // fail 函数体到第一个右花括号
            .first ?? ""
        XCTAssertTrue(failBody.contains("/usr/bin/open"), "fail 没有把应用重新打开")
        XCTAssertTrue(failBody.contains("failure_report"), "fail 没有留下失败原因")

        // 失败路径全部走 fail，不再有裸的 exit 1。
        XCTAssertFalse(
            script.contains("|| { log"),
            "还有绕过 fail 的失败路径，应用会被留在关闭状态"
        )
    }

    /// 只等不催的等待循环会在应用卡住退出时把用户留在中间态，adoption 必须用
    /// 与更新流程相同的那一份。
    func testAdoptionScriptWaitsWithTheEscalatingLoop() {
        let script = JarvisLocalSigning.adoptionScript(
            appURL: URL(fileURLWithPath: "/Applications/Jarvis.app"),
            bundleIdentifier: "com.jarvis.mac",
            workDirectory: URL(fileURLWithPath: "/tmp/JarvisAdopt-Test"),
            parentProcessID: 4242
        )
        XCTAssertTrue(script.contains("wait_ticks < 150"), "等待循环没有超时上限")
        XCTAssertTrue(script.contains("-TERM"), "等待循环没有升级到 TERM")
        XCTAssertTrue(script.contains("-KILL"), "等待循环没有升级到 KILL")
    }
}
