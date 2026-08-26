import Foundation

/// macOS Tahoe Control Center tracks third-party extras in
/// `group.com.apple.controlcenter` / `trackedApplications`.
///
/// A disallowed app can list another app's bundle under `menuItemLocations`.
/// When that happens, toggling the first app off also hides the second. ChatGPT
/// (`com.openai.codex`) currently records `com.jarvis.mac` this way, so Jarvis
/// disappears with ChatGPT. Repair keeps Jarvis only on its own record.
enum JarvisControlCenterMenuBarRepair {
    static let jarvisBundleIdentifier = "com.jarvis.mac"
    static let trackedApplicationsKey = "trackedApplications"

    struct RepairResult: Equatable {
        var removedForeignReferences: Int
        var forcedAllowed: Bool

        var didChange: Bool {
            removedForeignReferences > 0 || forcedAllowed
        }
    }

    static var controlCenterGroupPreferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist"
            )
    }

    static func bundleIdentifier(from identity: Any?) -> String? {
        guard let dictionary = identity as? [String: Any] else { return nil }
        if let bundle = dictionary["bundle"] as? [String: Any],
           let value = bundle["_0"] as? String
        {
            return value
        }
        if let location = dictionary["location"] {
            return bundleIdentifier(from: location)
        }
        return nil
    }

    @discardableResult
    static func repairTrackedApplications(_ entries: inout [Any]) -> RepairResult {
        var result = RepairResult(removedForeignReferences: 0, forcedAllowed: false)

        for index in entries.indices {
            guard var entry = entries[index] as? [String: Any] else { continue }
            var entryChanged = false
            let owner = bundleIdentifier(from: entry["location"]) ?? bundleIdentifier(from: entry)

            if let locations = entry["menuItemLocations"] as? [Any] {
                let filtered = locations.filter { location in
                    bundleIdentifier(from: location) != jarvisBundleIdentifier
                        || owner == jarvisBundleIdentifier
                }
                let removed = locations.count - filtered.count
                if removed > 0 {
                    entry["menuItemLocations"] = filtered
                    result.removedForeignReferences += removed
                    entryChanged = true
                }
            }

            if owner == jarvisBundleIdentifier, entry["isAllowed"] as? Bool == false {
                entry["isAllowed"] = true
                result.forcedAllowed = true
                entryChanged = true
            }

            if entryChanged {
                entries[index] = entry
            }
        }

        return result
    }

    @discardableResult
    static func repairPreferences(at url: URL, restartControlCenter: Bool = false) throws -> RepairResult {
        let data = try Data(contentsOf: url)
        var format: PropertyListSerialization.PropertyListFormat = .binary
        guard var outer = try PropertyListSerialization.propertyList(
            from: data,
            options: [.mutableContainersAndLeaves],
            format: &format
        ) as? [String: Any] else {
            return RepairResult(removedForeignReferences: 0, forcedAllowed: false)
        }

        var entries: [Any]
        var trackedFormat: PropertyListSerialization.PropertyListFormat = .binary
        if let trackedData = outer[trackedApplicationsKey] as? Data {
            guard let parsed = try PropertyListSerialization.propertyList(
                from: trackedData,
                options: [.mutableContainersAndLeaves],
                format: &trackedFormat
            ) as? [Any] else {
                return RepairResult(removedForeignReferences: 0, forcedAllowed: false)
            }
            entries = parsed
        } else if let parsed = outer[trackedApplicationsKey] as? [Any] {
            entries = parsed
        } else {
            return RepairResult(removedForeignReferences: 0, forcedAllowed: false)
        }

        let result = repairTrackedApplications(&entries)
        guard result.didChange else { return result }

        let innerData = try PropertyListSerialization.data(
            fromPropertyList: entries,
            format: .binary,
            options: 0
        )
        outer[trackedApplicationsKey] = innerData
        let outerData = try PropertyListSerialization.data(
            fromPropertyList: outer,
            format: format == .xml ? .xml : .binary,
            options: 0
        )

        // Control Center writes this plist from memory on exit. Kill it first so
        // it cannot restore the ChatGPT-owned copy of Jarvis after we save.
        if restartControlCenter {
            runKillall(["ControlCenter"])
            Thread.sleep(forTimeInterval: 0.25)
        }
        try outerData.write(to: url, options: .atomic)
        if restartControlCenter {
            runKillall(["cfprefsd"])
        }
        return result
    }

    /// Rewrites Control Center state if Jarvis is attached to another extra.
    @discardableResult
    static func repairSystemPreferencesIfNeeded() -> RepairResult {
        let url = controlCenterGroupPreferencesURL
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return RepairResult(removedForeignReferences: 0, forcedAllowed: false)
        }

        do {
            let result = try repairPreferences(at: url, restartControlCenter: true)
            if result.didChange {
                NSLog(
                    "Jarvis repaired Control Center menu tracking removedForeign=\(result.removedForeignReferences) forcedAllowed=\(result.forcedAllowed)"
                )
            }
            return result
        } catch {
            NSLog("Jarvis Control Center menu tracking repair failed: \(error.localizedDescription)")
            return RepairResult(removedForeignReferences: 0, forcedAllowed: false)
        }
    }

    private static func runKillall(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("Jarvis killall \(arguments.joined(separator: " ")) failed: \(error.localizedDescription)")
        }
    }
}
