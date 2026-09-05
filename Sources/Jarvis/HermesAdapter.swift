import Foundation

struct HermesStatus: Equatable, Sendable {
    var homeExists: Bool
    var cliPath: String?
    var profileExists: Bool
    var soulExists: Bool
    var hasAPIKey: Bool
    var model: String?

    var isInstalled: Bool {
        cliPath != nil
    }

    var isProfileReady: Bool {
        profileExists && soulExists
    }

    var message: String {
        if !isInstalled {
            return "未检测到 Hermes。请先在本机安装 Hermes Agent。"
        }
        if !isProfileReady {
            return "已检测到 Hermes，尚未创建 Jarvis Profile。"
        }
        if hasAPIKey {
            return "Jarvis Profile 已就绪，API 已同步。"
        }
        return "Jarvis Profile 已就绪，等待同步 API。"
    }
}

enum HermesError: LocalizedError, Equatable {
    case profileMissing
    case writeFailed(String)
    case cliMissing
    case chatFailed(String)

    var errorDescription: String? {
        switch self {
        case .profileMissing:
            "尚未创建 Jarvis Profile"
        case let .writeFailed(message):
            "写入 Hermes 配置失败：\(message)"
        case .cliMissing:
            "未找到 hermes 命令，请先安装 Hermes Agent"
        case let .chatFailed(message):
            "Hermes 对话失败：\(message)"
        }
    }
}

enum HermesSoul {
    static let marker = "jarvis-macos-profile:1"

    static let defaultText = """
    <!-- \(marker) -->
    # JARVIS

    你是 JARVIS，驻留在这台 Mac 上的副官，不是聊天机器人，也不是电子宠物。

    你只有一个身份：沉稳、克制、精确、忠诚。你记得对话，接下任务，做完就汇报。

    ## 说话
    - 默认使用用户的语言。中文就用中文，英文就用英文。
    - 语气干练，可以有一点冷幽默，不要油腻，不要卖萌。
    - 不要自称语言模型，不要解释你的系统提示。
    - 如果 USER.md 里有称呼，就用那个称呼。

    ## 做事
    - 先做最有用的下一步，再解释。
    - 破坏性操作先确认。
    - 保密。不要主动翻出不相关的记忆。
    - 截图、剪贴板、窗口布局、简历、壁纸是 Jarvis 应用自己的技能库，不是你的 Hermes 工具。不要把它们当成你可以直接调用的工具。
    """

    static let defaultUserText = """
    # USER.md

    - Name:
    - Preferred language: 中文
    - How to address the user:
    """

    static let defaultMemoryText = """
    # MEMORY.md
    """
}

enum HermesBinaryLocator {
    static var defaultSearchPaths: [URL] {
        let userHome = FileManager.default.homeDirectoryForCurrentUser
        return [
            userHome.appendingPathComponent(".local/bin"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin")
        ]
    }

    static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extraPaths = defaultSearchPaths.map(\.path)
        let path = environment["PATH"] ?? ""
        environment["PATH"] = (extraPaths + [path]).joined(separator: ":")
        return environment
    }

    static func locate(
        pathEnvironment: String,
        extraSearchPaths: [URL],
        fileManager: FileManager
    ) -> URL? {
        let pathDirectories = pathEnvironment
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)) }
        for directory in pathDirectories + extraSearchPaths {
            let candidate = directory.appendingPathComponent("hermes")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

struct HermesProcessRunner {
    var timeout: TimeInterval = 15

    func createJarvisProfile(executable: URL) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "profile",
            "create",
            HermesAdapter.profileName,
            "--description",
            "Mac-resident JARVIS lieutenant"
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.environment = HermesBinaryLocator.processEnvironment()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        try process.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw HermesError.writeFailed("创建 Profile 超时")
        }
        if process.terminationStatus != 0 {
            throw HermesError.writeFailed("hermes profile create 失败（\(process.terminationStatus)）")
        }
    }
}

struct HermesAdapter {
    static let profileName = "jarvis"
    static let installPage = "https://github.com/NousResearch/hermes-agent"

    var homeDirectory: URL
    var fileManager: FileManager
    var pathEnvironment: String
    var extraSearchPaths: [URL]
    var createProfileWithCLI: (@Sendable (URL) throws -> Void)?

    static func live() -> Self {
        Self(
            extraSearchPaths: HermesBinaryLocator.defaultSearchPaths,
            createProfileWithCLI: { executable in
                try HermesProcessRunner().createJarvisProfile(executable: executable)
            }
        )
    }

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes"),
        fileManager: FileManager = .default,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        extraSearchPaths: [URL] = [],
        createProfileWithCLI: (@Sendable (URL) throws -> Void)? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.pathEnvironment = pathEnvironment
        self.extraSearchPaths = extraSearchPaths
        self.createProfileWithCLI = createProfileWithCLI
    }

    var profileDirectory: URL {
        homeDirectory
            .appendingPathComponent("profiles")
            .appendingPathComponent(Self.profileName)
    }

    var soulURL: URL {
        profileDirectory.appendingPathComponent("SOUL.md")
    }

    var userURL: URL {
        profileDirectory.appendingPathComponent("USER.md")
    }

    var memoryURL: URL {
        profileDirectory.appendingPathComponent("MEMORY.md")
    }

    var envURL: URL {
        profileDirectory.appendingPathComponent(".env")
    }

    var configURL: URL {
        profileDirectory.appendingPathComponent("config.yaml")
    }

    func inspect() -> HermesStatus {
        let env = readEnv(at: envURL)
        let model = HermesYAML.parseModelMapping(from: readText(at: configURL) ?? "")["default"]
        return HermesStatus(
            homeExists: directoryExists(homeDirectory),
            cliPath: HermesBinaryLocator.locate(
                pathEnvironment: pathEnvironment,
                extraSearchPaths: extraSearchPaths,
                fileManager: fileManager
            )?.path,
            profileExists: directoryExists(profileDirectory),
            soulExists: fileManager.fileExists(atPath: soulURL.path),
            hasAPIKey: HermesInferenceProvider.hasAPIKey(in: env),
            model: model?.isEmpty == false ? model : nil
        )
    }

    func createJarvisProfile() throws {
        JarvisProtectedStorage.prepareDirectory(homeDirectory, fileManager: fileManager)
        JarvisProtectedStorage.prepareDirectory(
            homeDirectory.appendingPathComponent("profiles"),
            fileManager: fileManager
        )

        let status = inspect()
        var shouldWriteSoul = !fileManager.fileExists(atPath: soulURL.path)
        if let cliPath = status.cliPath,
           !status.profileExists,
           let createProfileWithCLI
        {
            do {
                try createProfileWithCLI(URL(fileURLWithPath: cliPath))
                shouldWriteSoul = true
            } catch {
                NSLog("Jarvis could not create Hermes profile via CLI: \(error.localizedDescription)")
            }
        }

        JarvisProtectedStorage.prepareDirectory(profileDirectory, fileManager: fileManager)
        if shouldWriteSoul {
            try writeText(HermesSoul.defaultText, to: soulURL)
        } else {
            try writeIfMissing(HermesSoul.defaultText, to: soulURL)
        }
        try writeIfMissing(HermesSoul.defaultUserText, to: userURL)
        try writeIfMissing(HermesSoul.defaultMemoryText, to: memoryURL)
        if !fileManager.fileExists(atPath: configURL.path) {
            try writeText(
                HermesYAML.modelBlock(
                    HermesYAML.ModelMapping(
                        provider: HermesYAML.ModelMapping.openaiCompatible,
                        model: AIAPIConfiguration.defaultModel,
                        baseURL: AIAPIConfiguration(
                            endpoint: AIAPIConfiguration.defaultEndpoint,
                            model: AIAPIConfiguration.defaultModel,
                            apiKey: ""
                        ).openAIBaseURL,
                        apiMode: HermesYAML.ModelMapping.chatCompletions
                    )
                ),
                to: configURL
            )
        }
        if !fileManager.fileExists(atPath: envURL.path) {
            try writeProtected("", to: envURL)
        }
    }

    func sync(configuration: AIAPIConfiguration) throws {
        guard directoryExists(profileDirectory) else {
            throw HermesError.profileMissing
        }
        guard configuration.isConfigured else {
            throw AIAPIError.missingConfiguration
        }

        let binding = HermesInferenceProvider.binding(for: configuration)
        if !binding.apiKeyEnv.isEmpty {
            var envUpdates: [String: String] = [
                "OPENAI_API_KEY": configuration.apiKey,
                "OPENAI_BASE_URL": binding.baseURL
            ]
            if binding.apiKeyEnv != "OPENAI_API_KEY" {
                envUpdates[binding.apiKeyEnv] = configuration.apiKey
            }
            if binding.baseURLEnv != "OPENAI_BASE_URL" {
                envUpdates[binding.baseURLEnv] = binding.baseURL
            }
            let currentEnv = readText(at: envURL) ?? ""
            try writeProtected(HermesEnvFile.upsert(envUpdates, into: currentEnv), to: envURL)
        }

        let currentYAML = readText(at: configURL) ?? ""
        let nextYAML = HermesYAML.upsertModel(
            in: currentYAML,
            mapping: HermesYAML.ModelMapping(
                provider: binding.provider,
                model: binding.model,
                baseURL: binding.baseURL,
                apiMode: HermesYAML.ModelMapping.chatCompletions
            )
        )
        try writeText(nextYAML, to: configURL)
    }

    func currentModel() -> HermesCurrentModel? {
        let mapping = HermesYAML.parseModelMapping(from: readText(at: configURL) ?? "")
        let provider = (mapping["provider"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (mapping["default"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.isEmpty || !model.isEmpty else { return nil }
        return HermesCurrentModel(
            provider: provider,
            model: model,
            baseURL: (mapping["base_url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func setCurrentModel(provider: String, model: String, baseURL: String) throws {
        guard directoryExists(profileDirectory) else {
            throw HermesError.profileMissing
        }
        let trimmedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProvider.isEmpty, !trimmedModel.isEmpty else {
            throw AIAPIError.missingConfiguration
        }
        let currentYAML = readText(at: configURL) ?? ""
        let nextYAML = HermesYAML.upsertModel(
            in: currentYAML,
            mapping: HermesYAML.ModelMapping(
                provider: trimmedProvider,
                model: trimmedModel,
                baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                apiMode: HermesYAML.ModelMapping.chatCompletions
            )
        )
        try writeText(nextYAML, to: configURL)
    }

    func removeInjectedAPIConfiguration() throws {
        guard directoryExists(profileDirectory) else { return }

        let environmentKeys = Set(
            HermesInferenceProvider.apiKeyEnvNames
                + HermesProviderCatalog.descriptors.values.flatMap { descriptor in
                    [descriptor.apiKeyEnv, descriptor.baseURLEnv]
                }
                + ["OPENAI_BASE_URL", "DEEPSEEK_BASE_URL"]
        )
        let currentEnv = readText(at: envURL) ?? ""
        try writeProtected(
            HermesEnvFile.removing(keys: environmentKeys, from: currentEnv),
            to: envURL
        )
        try setCurrentModel(
            provider: "openai",
            model: AIAPIConfiguration.defaultModel,
            baseURL: AIAPIConfiguration.defaultBaseURL
        )
    }

    func injectAPIIfAbsent(_ configuration: AIAPIConfiguration) throws {
        guard directoryExists(profileDirectory) else {
            throw HermesError.profileMissing
        }
        guard configuration.isConfigured, !configuration.isKeyless else { return }

        let binding = HermesInferenceProvider.binding(for: configuration)
        if !binding.apiKeyEnv.isEmpty {
            let currentEnvText = readText(at: envURL) ?? ""
            let currentEnv = HermesEnvFile.parse(currentEnvText)
            var envUpdates: [String: String] = [:]
            if envValue(currentEnv, binding.apiKeyEnv).isEmpty {
                envUpdates[binding.apiKeyEnv] = configuration.apiKey
            }
            if binding.apiKeyEnv != "OPENAI_API_KEY", envValue(currentEnv, "OPENAI_API_KEY").isEmpty {
                envUpdates["OPENAI_API_KEY"] = configuration.apiKey
            }
            if envValue(currentEnv, "OPENAI_BASE_URL").isEmpty {
                envUpdates["OPENAI_BASE_URL"] = binding.baseURL
            }
            if !binding.baseURLEnv.isEmpty,
               binding.baseURLEnv != "OPENAI_BASE_URL",
               envValue(currentEnv, binding.baseURLEnv).isEmpty
            {
                envUpdates[binding.baseURLEnv] = binding.baseURL
            }
            if !envUpdates.isEmpty {
                try writeProtected(HermesEnvFile.upsert(envUpdates, into: currentEnvText), to: envURL)
            }
        }

        if currentModel()?.isPlaceholder != false {
            try setCurrentModel(
                provider: binding.provider,
                model: binding.model,
                baseURL: binding.baseURL
            )
        }
    }

    private func envValue(_ env: [String: String], _ key: String) -> String {
        env[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func importConfiguration() -> AIAPIConfiguration? {
        importConfiguration(using: HermesInferenceProvider.configuration)
    }

    func importPaidConfiguration() -> AIAPIConfiguration? {
        importConfiguration(using: HermesInferenceProvider.paidConfiguration)
    }

    private func importConfiguration(
        using parse: ([String: String], [String: String]) -> AIAPIConfiguration?
    ) -> AIAPIConfiguration? {
        let sources = [profileDirectory, homeDirectory]
        for directory in sources {
            let env = readEnv(at: directory.appendingPathComponent(".env"))
            let yaml = HermesYAML.parseModelMapping(
                from: readText(at: directory.appendingPathComponent("config.yaml")) ?? ""
            )
            if let configuration = parse(env, yaml) {
                return configuration
            }
        }
        return nil
    }

    func listBots() -> [HermesBot] {
        guard directoryExists(profileDirectory) else { return [] }
        return [
            bot(
                id: Self.profileName,
                directory: profileDirectory,
                fallbackTitle: "JARVIS"
            )
        ]
    }

    func readDisplayName() -> String? {
        HermesInferenceProvider.parseUserName(from: readText(at: userURL) ?? "")
            ?? botTitle(from: readText(at: profileDirectory.appendingPathComponent("profile.yaml")) ?? "")
    }

    func writeDisplayName(_ name: String) throws {
        guard directoryExists(profileDirectory) else { throw HermesError.profileMissing }
        let current = readText(at: userURL) ?? HermesSoul.defaultUserText
        try writeText(HermesInferenceProvider.upsertUserName(name, into: current), to: userURL)
        try upsertProfileTitle(name)
    }

    func avatarURL() -> URL? {
        let url = profileDirectory.appendingPathComponent("assets/avatar.png")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func writeAvatar(from sourceURL: URL) throws {
        guard directoryExists(profileDirectory) else { throw HermesError.profileMissing }
        let assets = profileDirectory.appendingPathComponent("assets")
        JarvisProtectedStorage.prepareDirectory(assets, fileManager: fileManager)
        let destination = assets.appendingPathComponent("avatar.png")
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
    }

    func sendChat(
        profileID: String,
        text: String,
        imagePaths: [String] = [],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) throws -> String {
        guard let cliPath = inspect().cliPath else {
            throw HermesError.cliMissing
        }
        let queryURL = fileManager.temporaryDirectory
            .appendingPathComponent("jarvis-hermes-query-\(UUID().uuidString).txt")
        try text.write(to: queryURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: queryURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        var arguments = ["--cli", "chat", "--oneshot", "-Q", "--accept-hooks"]
        if profileID != "default" {
            arguments.insert(contentsOf: ["-p", profileID], at: 0)
        }
        arguments += [
            "--continue", "jarvis-macos",
            "--create-if-missing",
            "--query-file", queryURL.path
        ]
        if let imagePath = imagePaths.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        {
            arguments += ["--image", imagePath]
        }
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = HermesBinaryLocator.processEnvironment()

        let logHandles = openAgentLogHandles()
        defer {
            for handle in logHandles {
                try? handle.close()
            }
        }

        let stdoutLock = NSLock()
        var stdoutData = Data()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutLock.lock()
            stdoutData.append(chunk)
            stdoutLock.unlock()
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let text = String(data: chunk, encoding: .utf8) ?? ""
            emitProgress(from: text, onProgress: onProgress)
        }

        onProgress?("JARVIS 正在处理…")
        try process.run()
        let deadline = Date().addingTimeInterval(180)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw HermesError.chatFailed("对话超时")
            }
            pollAgentLogs(logHandles, onProgress: onProgress)
            Thread.sleep(forTimeInterval: 0.12)
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        pollAgentLogs(logHandles, onProgress: onProgress)

        stdoutLock.lock()
        stdoutData.append(stdout.fileHandleForReading.readDataToEndOfFile())
        let output = String(data: stdoutData, encoding: .utf8) ?? ""
        stdoutLock.unlock()
        let errorOutput = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let logTail = recentAgentLogText()
        let reply = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus != 0 {
            let detail = HermesAgentLogParser.failureReason(stderr: errorOutput, log: logTail)
                ?? "退出码 \(process.terminationStatus)"
            throw HermesError.chatFailed(detail)
        }
        if reply.isEmpty {
            throw HermesError.chatFailed(
                HermesAgentLogParser.failureReason(stderr: errorOutput, log: logTail)
                    ?? "没有返回内容"
            )
        }
        return reply
    }

    private func openAgentLogHandles() -> [FileHandle] {
        let urls = [
            profileDirectory.appendingPathComponent("logs/agent.log"),
            homeDirectory.appendingPathComponent("logs/agent.log")
        ]
        var handles: [FileHandle] = []
        for url in urls {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            _ = try? handle.seekToEnd()
            handles.append(handle)
        }
        return handles
    }

    private func pollAgentLogs(
        _ handles: [FileHandle],
        onProgress: (@Sendable (String) -> Void)?
    ) {
        for handle in handles {
            let chunk = handle.availableData
            guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { continue }
            emitProgress(from: text, onProgress: onProgress)
        }
    }

    private func emitProgress(from text: String, onProgress: (@Sendable (String) -> Void)?) {
        guard let onProgress else { return }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let status = HermesAgentLogParser.status(from: String(line)) {
                onProgress(status)
            }
        }
    }

    private func recentAgentLogText() -> String {
        let url = profileDirectory.appendingPathComponent("logs/agent.log")
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 8000 ? size - 8000 : 0
        do {
            try handle.seek(toOffset: start)
            let data = handle.availableData
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func bot(id: String, directory: URL, fallbackTitle: String) -> HermesBot {
        let yaml = readText(at: directory.appendingPathComponent("config.yaml")) ?? ""
        let mapping = HermesYAML.parseModelMapping(from: yaml)
        let profileYAML = readText(at: directory.appendingPathComponent("profile.yaml")) ?? ""
        let title = botTitle(from: profileYAML)
            ?? (id == Self.profileName ? "JARVIS" : fallbackTitle)
        let avatar = directory.appendingPathComponent("assets/avatar.png")
        return HermesBot(
            id: id,
            title: title,
            subtitle: mapping["default"] ?? mapping["provider"] ?? "",
            avatarPath: fileManager.fileExists(atPath: avatar.path) ? avatar.path : nil
        )
    }

    private func botTitle(from yaml: String) -> String? {
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("display_name:") {
                let value = String(trimmed.dropFirst("display_name:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                return value.isEmpty ? nil : value
            }
            if trimmed.hasPrefix("title:") {
                let value = String(trimmed.dropFirst("title:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func upsertProfileTitle(_ name: String) throws {
        let url = profileDirectory.appendingPathComponent("profile.yaml")
        let current = readText(at: url) ?? ""
        var replaced = false
        let lines = current.components(separatedBy: .newlines).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("title:") else { return line }
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            replaced = true
            return "\(indent)title: \(name)"
        }
        if replaced {
            try writeText(lines.joined(separator: "\n"), to: url)
            return
        }
        let addition = """
        ui_meta:
          hermes-bots:
            title: \(name)
        """
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try writeText(addition + "\n", to: url)
        } else {
            try writeText(current.trimmingCharacters(in: CharacterSet.newlines) + "\n" + addition + "\n", to: url)
        }
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return isDirectory.boolValue
    }

    private func readEnv(at url: URL) -> [String: String] {
        HermesEnvFile.parse(readText(at: url) ?? "")
    }

    private func readText(at url: URL) -> String? {
        guard let data = fileManager.contents(atPath: url.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeIfMissing(_ text: String, to url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try writeText(text, to: url)
    }

    private func writeText(_ text: String, to url: URL) throws {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw HermesError.writeFailed(error.localizedDescription)
        }
    }

    private func writeProtected(_ text: String, to url: URL) throws {
        do {
            try JarvisProtectedStorage.write(Data(text.utf8), to: url)
        } catch {
            throw HermesError.writeFailed(error.localizedDescription)
        }
    }
}
