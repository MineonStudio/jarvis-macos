import Foundation

extension JarvisUpdateService {
    static func launchServicesCleanupPaths(
        from dump: String,
        preserving currentAppURL: URL,
        bundleIdentifier: String
    ) -> [URL] {
        let currentPath = currentAppURL.standardizedFileURL.path
        let separator = String(repeating: "-", count: 80)
        var paths = Set<String>()

        for record in dump.components(separatedBy: separator) {
            let lines = record.components(separatedBy: .newlines)
            guard let identifierLine = lines.first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("identifier:")
            }) else {
                continue
            }

            let identifier = identifierLine
                .split(separator: ":", maxSplits: 1)
                .dropFirst()
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            guard let identifier,
                  identifier == bundleIdentifier
                  || identifier.hasPrefix("\(bundleIdentifier).")
                  || identifier == "com.example.jarvis-status-probe"
            else {
                continue
            }

            guard let pathLine = lines.first(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("path:")
            }) else {
                continue
            }

            var path = pathLine
                .split(separator: ":", maxSplits: 1)
                .dropFirst()
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let metadataStart = path.range(of: " (0x") {
                path = String(path[..<metadataStart.lowerBound])
            }

            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.pathExtension.lowercased() == "app", url.path != currentPath else {
                continue
            }
            paths.insert(url.path)
        }

        return paths.sorted().map(URL.init(fileURLWithPath:))
    }

    func cleanupStaleLaunchServices() {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              FileManager.default.isExecutableFile(atPath: lsregisterPath)
        else {
            return
        }

        let dumpProcess = Process()
        let outputPipe = Pipe()
        dumpProcess.executableURL = URL(fileURLWithPath: lsregisterPath)
        dumpProcess.arguments = ["-dump"]
        dumpProcess.standardOutput = outputPipe
        dumpProcess.standardError = FileHandle.nullDevice

        do {
            try dumpProcess.run()
            dumpProcess.waitUntilExit()
        } catch {
            return
        }

        guard dumpProcess.terminationStatus == 0,
              let dump = String(
                  data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                  encoding: .utf8
              )
        else {
            return
        }

        let stalePaths = Self.launchServicesCleanupPaths(
            from: dump,
            preserving: Bundle.main.bundleURL,
            bundleIdentifier: bundleIdentifier
        )
        for path in stalePaths {
            let unregisterProcess = Process()
            unregisterProcess.executableURL = URL(fileURLWithPath: lsregisterPath)
            unregisterProcess.arguments = ["-u", path.path]
            unregisterProcess.standardOutput = FileHandle.nullDevice
            unregisterProcess.standardError = FileHandle.nullDevice
            try? unregisterProcess.run()
            unregisterProcess.waitUntilExit()
        }
    }
}
