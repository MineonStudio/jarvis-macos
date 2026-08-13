import AppKit
import CryptoKit
import Foundation

enum JarvisAppVersion {
    static let repositoryURL = URL(string: "https://github.com/MineonStudio/jarvis-macos")!
    static let releasesURL = URL(string: "https://github.com/MineonStudio/jarvis-macos/releases")!

    private static let fallbackShortVersion = "0.5.2"
    private static let fallbackBuild = "76"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackShortVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? fallbackBuild
    }

    static var displayName: String {
        "v\(shortVersion) (构建 \(build))"
    }
}

struct JarvisReleaseInfo: Equatable {
    let version: String
    let releaseURL: URL
    let downloadURL: URL?
    let assetDigest: String?
}

enum JarvisUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(JarvisReleaseInfo)
    case downloading(version: String)
    case installing(version: String)
    case failed(message: String)
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

enum JarvisUpdateError: LocalizedError {
    case downloadUnavailable
    case invalidArchive
    case invalidApplication
    case unsupportedInstallLocation
    case toolFailed(String)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .downloadUnavailable:
            return "该版本没有可用的应用安装包"
        case .invalidArchive:
            return "更新包格式无效"
        case .invalidApplication:
            return "更新包中的贾维斯应用无效"
        case .unsupportedInstallLocation:
            return "当前应用不是从标准 macOS 应用包启动，无法自动更新"
        case .toolFailed(let message):
            return "解压更新包失败：\(message)"
        case .checksumMismatch:
            return "更新包校验失败，未进行安装"
        }
    }
}

struct JarvisUpdateService {
    func checkForLatestRelease() async throws -> JarvisReleaseInfo {
        let endpoint = URL(string: "https://api.github.com/repos/MineonStudio/jarvis-macos/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else {
            throw URLError(.resourceUnavailable)
        }

        let asset = release.assets.first { asset in
            let name = asset.name.lowercased()
            return name.contains("jarvis") && name.hasSuffix(".zip")
        }
        return JarvisReleaseInfo(
            version: release.tagName,
            releaseURL: release.htmlURL,
            downloadURL: asset?.browserDownloadURL,
            assetDigest: asset?.digest
        )
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = versionParts(remote)
        let localParts = versionParts(local)
        guard !remoteParts.isEmpty, !localParts.isEmpty else { return remote != local }

        for index in 0..<max(remoteParts.count, localParts.count) {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    /// Downloads, validates, stages, and hands the update to a detached
    /// installer. The current app is not replaced until this method returns.
    func downloadAndInstall(_ release: JarvisReleaseInfo) async throws {
        guard let downloadURL = release.downloadURL else {
            throw JarvisUpdateError.downloadUnavailable
        }

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("JarvisUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryDirectory.path)
        var handedOffToInstaller = false

        defer {
            if !handedOffToInstaller {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        var request = URLRequest(url: downloadURL)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (downloadedURL, response) = try await URLSession.shared.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let archiveURL = temporaryDirectory.appendingPathComponent("Jarvis-update.zip")
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)
        try verifyDigest(of: archiveURL, expected: release.assetDigest)

        let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try runTool(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
        )

        guard let newAppURL = findApplication(in: extractionDirectory),
              isValidApplicationBundle(newAppURL) else {
            throw JarvisUpdateError.invalidApplication
        }

        let currentAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard currentAppURL.pathExtension.lowercased() == "app",
              currentAppURL.lastPathComponent == "Jarvis.app" else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }

        let scriptURL = temporaryDirectory.appendingPathComponent("install-update.zsh")
        try makeInstallerScript(
            at: scriptURL,
            currentAppURL: currentAppURL,
            newAppURL: newAppURL,
            temporaryDirectory: temporaryDirectory,
            parentProcessID: ProcessInfo.processInfo.processIdentifier
        )

        let installer = Process()
        // Keep the installer alive after Jarvis exits. A detached shell is
        // required here because the updater must replace the bundle that owns
        // the current process and then launch it again.
        installer.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        installer.arguments = ["/bin/zsh", scriptURL.path]
        installer.standardOutput = FileHandle.nullDevice
        installer.standardError = FileHandle.nullDevice
        try installer.run()
        handedOffToInstaller = true
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    private func verifyDigest(of fileURL: URL, expected: String?) throws {
        guard let expected, expected.hasPrefix("sha256:") else { return }
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest.caseInsensitiveCompare(String(expected.dropFirst("sha256:".count))) == .orderedSame else {
            throw JarvisUpdateError.checksumMismatch
        }
    }

    private func findApplication(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app" && url.lastPathComponent == "Jarvis.app" {
                return url
            }
        }
        return nil
    }

    private func isValidApplicationBundle(_ url: URL) -> Bool {
        let executableURL = url.appendingPathComponent("Contents/MacOS/Jarvis")
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.isReadableFile(atPath: executableURL.path),
              FileManager.default.isReadableFile(atPath: infoURL.path),
              let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String else {
            return false
        }
        return bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func runTool(_ path: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "未知错误"
            throw JarvisUpdateError.toolFailed(message)
        }
    }

    private func makeInstallerScript(
        at scriptURL: URL,
        currentAppURL: URL,
        newAppURL: URL,
        temporaryDirectory: URL,
        parentProcessID: Int32
    ) throws {
        let backupURL = currentAppURL.deletingLastPathComponent()
            .appendingPathComponent("Jarvis.app.update-backup-\(UUID().uuidString)")
        let script = """
        #!/bin/zsh
        set -u
        old_app=\(shellQuote(currentAppURL.path))
        new_app=\(shellQuote(newAppURL.path))
        backup_app=\(shellQuote(backupURL.path))
        temp_dir=\(shellQuote(temporaryDirectory.path))
        parent_pid=\(parentProcessID)

        # Wait for a clean termination, but do not block forever if AppKit
        # leaves the process as a zombie or a termination request is ignored.
        wait_ticks=0
        while /bin/kill -0 "$parent_pid" 2>/dev/null && (( wait_ticks < 150 )); do
            process_state=$(/bin/ps -p "$parent_pid" -o stat= 2>/dev/null || true)
            [[ "$process_state" == Z* ]] && break
            /bin/sleep 0.1
            (( wait_ticks += 1 ))
        done
        if /bin/kill -0 "$parent_pid" 2>/dev/null; then
            /bin/kill -TERM "$parent_pid" 2>/dev/null || true
            /bin/sleep 0.5
            /bin/kill -KILL "$parent_pid" 2>/dev/null || true
        fi
        /bin/sleep 0.4

        if /bin/mv "$old_app" "$backup_app" 2>/dev/null; then
            if /usr/bin/ditto "$new_app" "$old_app" 2>/dev/null; then
                /bin/rm -rf "$backup_app"
                # The current distribution is ad-hoc signed, so macOS may
                # associate Screen Recording with the previous code identity.
                # Reset only after a successful replacement and let the new
                # app request the native permission again on first capture.
                /usr/bin/tccutil reset ScreenCapture com.jarvis.mac >/dev/null 2>&1 || true
                /usr/bin/open -na "$old_app"
                /bin/rm -rf "$temp_dir"
                exit 0
            fi
            /bin/mv "$backup_app" "$old_app" 2>/dev/null || true
        fi

        # /Applications may be owned by root. Ask macOS for authorization only
        # when the normal user-owned replacement is denied.
        if ! /usr/bin/osascript - "$old_app" "$new_app" "$backup_app" "$temp_dir" <<'APPLESCRIPT'
        on run argv
            set oldApp to item 1 of argv
            set newApp to item 2 of argv
            set backupApp to item 3 of argv
            set tempDir to item 4 of argv
            set command to "/bin/mv " & quoted form of oldApp & " " & quoted form of backupApp & " && if /usr/bin/ditto " & quoted form of newApp & " " & quoted form of oldApp & "; then /bin/rm -rf " & quoted form of backupApp & " " & quoted form of tempDir & "; else /bin/mv " & quoted form of backupApp & " " & quoted form of oldApp & "; exit 1; end if"
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
        then
            exit 1
        fi
        /usr/bin/tccutil reset ScreenCapture com.jarvis.mac >/dev/null 2>&1 || true
        /usr/bin/open -na "$old_app"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
