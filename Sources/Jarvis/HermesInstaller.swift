import Foundation

struct HermesInstaller {
    static let installScriptURL = URL(string: "https://hermes-agent.nousresearch.com/install.sh")!
    static let installArguments = ["--skip-setup", "--non-interactive"]

    var fileManager: FileManager = .default
    var scriptURL: URL = HermesInstaller.installScriptURL

    static func live() -> Self {
        Self()
    }

    func install(onOutput: @escaping @Sendable (String) -> Void = { _ in }) throws {
        let scriptFile = fileManager.temporaryDirectory
            .appendingPathComponent("jarvis-hermes-installer-\(UUID().uuidString).sh")
        defer { try? fileManager.removeItem(at: scriptFile) }

        try runProcess(
            executable: "/usr/bin/curl",
            arguments: [
                "--fail",
                "--silent",
                "--show-error",
                "--location",
                "--proto",
                "=https",
                "--tlsv1.2",
                "--output",
                scriptFile.path,
                scriptURL.absoluteString
            ],
            onOutput: onOutput
        )

        try runProcess(
            executable: "/bin/bash",
            arguments: [scriptFile.path] + Self.installArguments,
            onOutput: onOutput
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = processEnvironment()

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            onOutput(String(data: data, encoding: .utf8) ?? "")
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw HermesError.installFailed("无法启动安装程序：\(error.localizedDescription)")
        }

        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        let remaining = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty {
            onOutput(String(data: remaining, encoding: .utf8) ?? "")
        }

        guard process.terminationStatus == 0 else {
            throw HermesError.installFailed("官方安装脚本失败（退出码 \(process.terminationStatus)）")
        }
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            environment["PATH"] ?? ""
        ]
        var seen = Set<String>()
        environment["PATH"] = paths
            .flatMap { $0.split(separator: ":").map(String.init) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        environment.removeValue(forKey: "PYTHONPATH")
        environment.removeValue(forKey: "PYTHONHOME")
        return environment
    }
}
