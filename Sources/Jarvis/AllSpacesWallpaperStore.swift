import Foundation

enum AllSpacesWallpaperStoreError: LocalizedError, Equatable {
    case missingStore
    case invalidStore
    case agentRestartFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingStore:
            "macOS 墙纸配置不可用"
        case .invalidStore:
            "macOS 墙纸配置格式无法识别"
        case let .agentRestartFailed(status):
            "macOS 墙纸服务刷新失败（状态码 \(status)）"
        }
    }
}

/// Updates the per-user WallpaperAgent store used by macOS's “Show on All
/// Spaces” mode. NSWorkspace's public API only targets the current Space.
struct AllSpacesWallpaperStore {
    static let defaultIndexURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    private let indexURL: URL
    private let restartAgent: () throws -> Void

    init(
        indexURL: URL = Self.defaultIndexURL,
        restartAgent: @escaping () throws -> Void = AllSpacesWallpaperStore.restartWallpaperAgent
    ) {
        self.indexURL = indexURL
        self.restartAgent = restartAgent
    }

    func apply(imageURL: URL) throws {
        let originalData: Data
        do {
            originalData = try Data(contentsOf: indexURL)
        } catch {
            throw AllSpacesWallpaperStoreError.missingStore
        }

        let root: [String: Any]
        do {
            root = try PropertyListSerialization.propertyList(
                from: originalData,
                options: [.mutableContainersAndLeaves],
                format: nil
            ) as? [String: Any] ?? [:]
        } catch {
            throw AllSpacesWallpaperStoreError.invalidStore
        }

        guard !root.isEmpty else {
            throw AllSpacesWallpaperStoreError.invalidStore
        }

        let updatedRoot: [String: Any]
        do {
            updatedRoot = try Self.rootByApplying(imageURL: imageURL, to: root)
        } catch {
            throw AllSpacesWallpaperStoreError.invalidStore
        }

        let updatedData: Data
        do {
            updatedData = try PropertyListSerialization.data(
                fromPropertyList: updatedRoot,
                format: .binary,
                options: 0
            )
        } catch {
            throw AllSpacesWallpaperStoreError.invalidStore
        }

        do {
            try updatedData.write(to: indexURL, options: .atomic)
            try restartAgent()
        } catch let error as AllSpacesWallpaperStoreError {
            restore(originalData)
            throw error
        } catch {
            restore(originalData)
            throw error
        }
    }

    private func restore(_ data: Data) {
        try? data.write(to: indexURL, options: .atomic)
        try? restartAgent()
    }

    private static func rootByApplying(imageURL: URL, to root: [String: Any]) throws -> [String: Any] {
        let imageConfiguration = try PropertyListSerialization.data(
            fromPropertyList: [
                "type": "imageFile",
                "url": ["relative": imageURL.absoluteString]
            ],
            format: .binary,
            options: 0
        )

        let fallbackDesktop = desktopConfiguration(in: root)
        var allSpaces = dictionary(root["AllSpacesAndDisplays"])
        var desktop = dictionary(allSpaces["Desktop"])
        if desktop.isEmpty {
            desktop = fallbackDesktop
        }

        let fallbackContent = dictionary(fallbackDesktop["Content"])
        var content = dictionary(desktop["Content"])
        if content.isEmpty {
            content = fallbackContent
        }

        var choices = dictionaryArray(content["Choices"])
        if choices.isEmpty {
            choices = dictionaryArray(fallbackContent["Choices"])
        }

        var choice = choices.first ?? [:]
        choice["Configuration"] = imageConfiguration
        choice["Files"] = [Any]()
        choice["Provider"] = "com.apple.wallpaper.choice.image"
        if choices.isEmpty {
            choices = [choice]
        } else {
            choices[0] = choice
        }

        content["Choices"] = choices
        content["Shuffle"] = content["Shuffle"] ?? "$null"
        desktop["Content"] = content
        desktop["LastSet"] = Date()
        desktop["LastUse"] = Date()
        allSpaces["Desktop"] = desktop
        allSpaces["Type"] = "desktop"

        var updatedRoot = root
        updatedRoot["AllSpacesAndDisplays"] = allSpaces
        return updatedRoot
    }

    private static func desktopConfiguration(in root: [String: Any]) -> [String: Any] {
        if let systemDefault = dictionary(root["SystemDefault"])["Desktop"] as? [String: Any] {
            return systemDefault
        }

        let spaces = dictionary(root["Spaces"])
        for space in spaces.values {
            let defaultDesktop = dictionary(dictionary(space)["Default"])["Desktop"] as? [String: Any]
            if let defaultDesktop {
                return defaultDesktop
            }
        }

        return [:]
    }

    private static func dictionary(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private static func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { $0 as? [String: Any] }
    }

    private static func restartWallpaperAgent() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        // Exit status 1 means the agent was not running. launchd will start it
        // when the desktop next needs it, so the plist update is still valid.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw AllSpacesWallpaperStoreError.agentRestartFailed(process.terminationStatus)
        }
    }
}
