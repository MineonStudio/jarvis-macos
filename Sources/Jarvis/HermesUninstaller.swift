import Foundation

enum HermesUninstallMode: String, Sendable {
    case standard
    case complete

    var choiceTitle: String {
        switch self {
        case .standard:
            "普通卸载"
        case .complete:
            "完全卸载"
        }
    }

    var choiceDescription: String {
        switch self {
        case .standard:
            "移除 CLI 和运行依赖，保留 Profile、配置与会话。"
        case .complete:
            "连同所有 Profile、配置、会话和本地数据一起删除。"
        }
    }

    var confirmationTitle: String {
        "确认\(choiceTitle) Hermes？"
    }

    var confirmationMessage: String {
        switch self {
        case .standard:
            "将移除 Hermes CLI、本地运行依赖和启动器，但保留 Hermes Profile、配置与会话。之后可以重新部署并继续使用。"
        case .complete:
            "将移除 Hermes CLI、本地运行依赖、所有 Profile、配置、会话和 Hermes 数据。此操作不可撤销。"
        }
    }

    var actionTitle: String {
        choiceTitle
    }
}

struct HermesUninstaller {
    private static let launcherNames = [
        "hermes",
        "hermes-agent",
        "hermes-acp",
        "node",
        "npm",
        "npx"
    ]

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let commandDirectories: [URL]

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        commandDirectories: [URL]? = nil
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.commandDirectories = commandDirectories ?? [
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        ]
    }

    var hermesHomeDirectory: URL {
        homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
    }

    func uninstall(mode: HermesUninstallMode = .complete) throws {
        for commandDirectory in commandDirectories {
            for launcherName in Self.launcherNames {
                try removeManagedLauncher(
                    at: commandDirectory.appendingPathComponent(launcherName)
                )
            }
        }

        switch mode {
        case .standard:
            try removeStandardRuntime()
        case .complete:
            guard fileManager.fileExists(atPath: hermesHomeDirectory.path) else { return }
            try fileManager.removeItem(at: hermesHomeDirectory)
        }
    }

    private func removeStandardRuntime() throws {
        let runtimePaths = [
            hermesHomeDirectory.appendingPathComponent("hermes-agent", isDirectory: true),
            hermesHomeDirectory.appendingPathComponent("node", isDirectory: true),
            hermesHomeDirectory.appendingPathComponent("bin/uv"),
            hermesHomeDirectory.appendingPathComponent("bin/uvx")
        ]
        for runtimePath in runtimePaths where fileManager.fileExists(atPath: runtimePath.path) {
            try fileManager.removeItem(at: runtimePath)
        }
    }

    private func removeManagedLauncher(at url: URL) throws {
        guard pathExistsIncludingDanglingSymlink(at: url) else { return }

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
            let destinationURL = URL(
                fileURLWithPath: destination,
                relativeTo: url.deletingLastPathComponent()
            ).standardizedFileURL
            guard isInsideHermesHome(destinationURL) else { return }
            try fileManager.removeItem(at: url)
            return
        }

        guard let contents = try? String(contentsOf: url, encoding: .utf8),
              contents.contains(hermesHomeDirectory.path)
        else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func pathExistsIncludingDanglingSymlink(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
            || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func isInsideHermesHome(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let root = hermesHomeDirectory.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }
}
