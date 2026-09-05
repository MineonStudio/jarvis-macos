import Foundation

enum HermesDeploymentPhase: Equatable, Sendable {
    case idle
    case installing
    case preparingSecurity
    case preparingProfile
    case configuring
    case cancelling
    case failed
}

enum HermesInstallerError: LocalizedError, Equatable {
    case invalidResponse
    case timedOut
    case cancelled
    case failed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无法连接 Hermes 官方安装源"
        case .timedOut:
            return "Hermes 部署超时，请稍后重试"
        case .cancelled:
            return "Hermes 部署已停止"
        case let .failed(status, output):
            let detail = HermesInstaller.lastMeaningfulLine(in: output)
            if detail.isEmpty {
                return "Hermes 安装程序未完成（\(status)）"
            }
            return "Hermes 安装程序未完成：\(detail)"
        }
    }
}

final class HermesInstallerControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancelled
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }

    func detach(_ process: Process) {
        lock.lock()
        defer { lock.unlock() }
        if self.process === process {
            self.process = nil
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()

        process?.terminate()
    }
}

struct HermesInstaller {
    static let scriptURL = URL(string: "https://hermes-agent.nousresearch.com/install.sh")!
    static let timeout: TimeInterval = 30 * 60

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func install(
        control: HermesInstallerControl,
        onOutput: @escaping (String) -> Void
    ) async throws {
        do {
            try Task.checkCancellation()
            guard !control.isCancelled else { throw HermesInstallerError.cancelled }

            var request = URLRequest(url: Self.scriptURL)
            request.setValue(
                "Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos",
                forHTTPHeaderField: "User-Agent"
            )
            request.setValue("text/plain", forHTTPHeaderField: "Accept")

            let (downloadedURL, response) = try await URLSession.shared.download(for: request)
            try Task.checkCancellation()
            guard !control.isCancelled else { throw HermesInstallerError.cancelled }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode)
            else {
                throw HermesInstallerError.invalidResponse
            }

            let temporaryDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("JarvisHermesInstall-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            defer { try? fileManager.removeItem(at: temporaryDirectory) }

            let scriptURL = temporaryDirectory.appendingPathComponent("install.sh")
            try fileManager.moveItem(at: downloadedURL, to: scriptURL)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            try runInstaller(at: scriptURL, control: control, onOutput: onOutput)
        } catch {
            if control.isCancelled || error is CancellationError {
                throw HermesInstallerError.cancelled
            }
            throw error
        }
    }

    private func runInstaller(
        at scriptURL: URL,
        control: HermesInstallerControl,
        onOutput: @escaping (String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, "--skip-setup", "--non-interactive"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = HermesBinaryLocator.processEnvironment()

        let standardOutput = Pipe()
        let standardError = Pipe()
        let outputBuffer = HermesInstallerOutputBuffer()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let consume: (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else {
                return
            }
            if let line = outputBuffer.append(text) {
                onOutput(line)
            }
        }
        standardOutput.fileHandleForReading.readabilityHandler = consume
        standardError.fileHandleForReading.readabilityHandler = consume

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }

        defer {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            throw error
        }
        control.attach(process)
        defer { control.detach(process) }

        if control.isCancelled {
            process.terminate()
        }

        guard termination.wait(timeout: .now() + Self.timeout) == .success else {
            process.terminate()
            throw HermesInstallerError.timedOut
        }

        if control.isCancelled {
            throw HermesInstallerError.cancelled
        }

        let trailingOutput = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let trailingError = standardError.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: trailingOutput, encoding: .utf8), !text.isEmpty {
            if let line = outputBuffer.append(text) {
                onOutput(line)
            }
        }
        if let text = String(data: trailingError, encoding: .utf8), !text.isEmpty {
            if let line = outputBuffer.append(text) {
                onOutput(line)
            }
        }

        guard process.terminationStatus == 0 else {
            throw HermesInstallerError.failed(
                status: process.terminationStatus,
                output: outputBuffer.text
            )
        }
    }

    static func lastMeaningfulLine(in output: String) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .reversed()
            .map { cleanLine(String($0)) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    fileprivate static func cleanLine(_ line: String) -> String {
        let withoutANSI = line.replacingOccurrences(
            of: #"\u001B\[[0-9;]*[[:alpha:]]"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = withoutANSI.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.suffix(240))
    }
}

private final class HermesInstallerOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func append(_ chunk: String) -> String? {
        lock.lock()
        value.append(chunk)
        if value.count > 16000 {
            value = String(value.suffix(8000))
        }
        let line = value
            .split(whereSeparator: \.isNewline)
            .reversed()
            .map { HermesInstaller.cleanLine(String($0)) }
            .first(where: { !$0.isEmpty })
        lock.unlock()
        return line
    }
}

enum HermesSecurityInstallerError: LocalizedError, Equatable {
    case runtimeMissing
    case timedOut
    case cancelled
    case failed(output: String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            return "Hermes 已安装，但未找到安全组件运行环境"
        case .timedOut:
            return "Hermes 安全组件准备超时，请稍后重试"
        case .cancelled:
            return "Hermes 部署已停止"
        case let .failed(output):
            let detail = HermesInstaller.lastMeaningfulLine(in: output)
            if detail.isEmpty {
                return "Hermes 安全组件准备失败"
            }
            return "Hermes 安全组件准备失败：\(detail)"
        }
    }
}

struct HermesTirithInstaller {
    static let timeout: TimeInterval = 15 * 60

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func install(
        control: HermesInstallerControl,
        onOutput: @escaping (String) -> Void
    ) throws {
        let adapter = HermesAdapter.live()
        let agentDirectory = adapter.homeDirectory.appendingPathComponent("hermes-agent")
        let pythonURL = agentDirectory.appendingPathComponent("venv/bin/python")
        guard fileManager.isExecutableFile(atPath: pythonURL.path) else {
            throw HermesSecurityInstallerError.runtimeMissing
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-c", Self.pythonScript]
        process.currentDirectoryURL = agentDirectory

        var environment = HermesBinaryLocator.processEnvironment()
        let profileBin = adapter.profileDirectory.appendingPathComponent("bin").path
        environment["HERMES_HOME"] = adapter.profileDirectory.path
        environment["PATH"] = [profileBin, environment["PATH"] ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        process.environment = environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        let outputBuffer = HermesInstallerOutputBuffer()
        process.standardOutput = standardOutput
        process.standardError = standardError

        let consume: (FileHandle) -> Void = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)
            else {
                return
            }
            if let line = outputBuffer.append(text) {
                onOutput(line)
            }
        }
        standardOutput.fileHandleForReading.readabilityHandler = consume
        standardError.fileHandleForReading.readabilityHandler = consume

        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            termination.signal()
        }

        defer {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            throw HermesSecurityInstallerError.failed(output: error.localizedDescription)
        }
        control.attach(process)
        defer { control.detach(process) }

        if control.isCancelled {
            process.terminate()
        }

        guard termination.wait(timeout: .now() + Self.timeout) == .success else {
            process.terminate()
            throw HermesSecurityInstallerError.timedOut
        }

        if control.isCancelled {
            throw HermesSecurityInstallerError.cancelled
        }

        let trailingOutput = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let trailingError = standardError.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: trailingOutput, encoding: .utf8), !text.isEmpty {
            if let line = outputBuffer.append(text) {
                onOutput(line)
            }
        }
        if let text = String(data: trailingError, encoding: .utf8), !text.isEmpty {
            if let line = outputBuffer.append(text) {
                onOutput(line)
            }
        }

        guard process.terminationStatus == 0 else {
            throw HermesSecurityInstallerError.failed(output: outputBuffer.text)
        }
    }

    static let pythonScript = """
    import os
    import sys
    from tools import tirith_security

    if not tirith_security.is_platform_supported():
        print("Tirith is not supported on this platform", file=sys.stderr)
        raise SystemExit(1)

    resolved = tirith_security._resolve_tirith_path("tirith")
    if not resolved or not os.path.isfile(resolved) or not os.access(resolved, os.X_OK):
        print("Tirith installation did not produce an executable", file=sys.stderr)
        raise SystemExit(1)

    print(f"Tirith ready: {resolved}")
    """
}
