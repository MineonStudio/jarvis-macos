import AppKit
import CoreServices
import CryptoKit
import Foundation
import Security

enum JarvisAppVersion {
    private static let fallbackShortVersion = "1.4.3"
    private static let fallbackBuild = "341"

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
    let build: String?
    let releaseURL: URL
    let downloadURL: URL?
    let assetDigest: String?
    let archiveSize: Int64
    let isLegacyBootstrap: Bool
}

enum JarvisUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(JarvisReleaseInfo)
    case downloading(version: String)
    case readyToInstall(version: String)
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
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
        case size
    }
}

enum JarvisUpdateError: LocalizedError {
    case downloadUnavailable
    case invalidArchive
    case invalidApplication
    case invalidManifest
    case invalidManifestSignature
    case missingSignedManifest
    case mismatchedVersion
    case unsupportedInstallLocation
    case ambiguousInstallLocation
    case unsupportedUpdateChannel
    case toolFailed(String)
    case checksumUnavailable
    case checksumMismatch
    case privacyPermissionResetFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadUnavailable:
            "该版本没有可用的应用安装包"
        case .invalidArchive:
            "更新包格式无效"
        case .invalidApplication:
            "更新包中的贾维斯应用无效"
        case .invalidManifest:
            "更新清单无效或与发布版本不匹配"
        case .invalidManifestSignature:
            "更新清单签名校验失败，已阻止安装"
        case .missingSignedManifest:
            "该版本缺少可信更新签名，已阻止安装"
        case .mismatchedVersion:
            "更新包内的版本与发布信息不一致，已阻止安装"
        case .unsupportedInstallLocation:
            "当前应用位于只读磁盘映像或临时转移路径，无法自动更新。请先将贾维斯复制到“应用程序”文件夹后重试"
        case .ambiguousInstallLocation:
            "检测到多个贾维斯安装副本，无法确定要更新哪一个。请保留一个安装副本后重试"
        case .unsupportedUpdateChannel:
            "开发版不使用正式版更新通道"
        case let .toolFailed(message):
            "解压更新包失败：\(message)"
        case .checksumUnavailable:
            "更新包缺少 SHA-256 校验信息，未进行安装"
        case .checksumMismatch:
            "更新包校验失败，未进行安装"
        case let .privacyPermissionResetFailed(message):
            "清除旧的屏幕录制和辅助功能权限失败：\(message)"
        }
    }
}

struct JarvisUpdateService {
    private static let legacyBootstrapMaximumVersion = "1.4.5"
    private static let manifestAssetName = "Jarvis-update-manifest.json"
    private static let signatureAssetName = "Jarvis-update-manifest.sig"
    static let updateLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Jarvis/update.log")

    static func privacyPermissionResetArguments(bundleIdentifier: String) -> [[String]] {
        JarvisPrivacyPermissionReset.arguments(bundleIdentifier: bundleIdentifier)
    }

    func checkForLatestRelease() async throws -> JarvisReleaseInfo {
        guard Bundle.main.bundleIdentifier == "com.jarvis.mac" else {
            throw JarvisUpdateError.unsupportedUpdateChannel
        }
        let operationID = JarvisLog.operationID()
        JarvisLog.info(
            category: .update,
            event: "release.check.begin",
            operationID: operationID
        )
        let endpoint = URL(string: "https://api.github.com/repos/MineonStudio/jarvis-macos/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await updateSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else {
            throw URLError(.resourceUnavailable)
        }

        let manifestAsset = release.assets.first { $0.name == Self.manifestAssetName }
        let signatureAsset = release.assets.first { $0.name == Self.signatureAssetName }
        let releaseInfo: JarvisReleaseInfo
        if let manifestAsset, let signatureAsset {
            let manifestData = try await downloadSmallAsset(
                manifestAsset,
                maximumBytes: JarvisUpdateSecurity.maximumManifestBytes
            )
            let signatureData = try await downloadSmallAsset(
                signatureAsset,
                maximumBytes: JarvisUpdateSecurity.maximumSignatureBytes
            )
            guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "JarvisUpdatePublicKey") as? String else {
                throw JarvisUpdateError.invalidManifestSignature
            }
            let manifest = try JarvisUpdateSecurity.verifyManifest(
                data: manifestData,
                signatureData: signatureData,
                publicKeyBase64: publicKey
            )
            guard JarvisUpdateSecurity.normalizedVersion(release.tagName) == manifest.version else {
                throw JarvisUpdateError.invalidManifest
            }
            guard let archive = release.assets.first(where: { $0.name == manifest.archiveName }),
                  archive.size > 0,
                  archive.size <= JarvisUpdateSecurity.maximumArchiveBytes,
                  isAllowedGitHubAssetURL(archive.browserDownloadURL)
            else {
                throw JarvisUpdateError.downloadUnavailable
            }
            releaseInfo = JarvisReleaseInfo(
                version: manifest.version,
                build: manifest.build,
                releaseURL: release.htmlURL,
                downloadURL: archive.browserDownloadURL,
                assetDigest: "sha256:\(manifest.sha256)",
                archiveSize: archive.size,
                isLegacyBootstrap: false
            )
        } else if manifestAsset == nil, signatureAsset == nil,
                  isLegacyBootstrapRelease(release.tagName)
        {
            // One-time bridge for installs that predate the pinned key. Only
            // the already-published 1.4.5 release may use GitHub's digest.
            let versionSuffix = JarvisUpdateSecurity.normalizedVersion(release.tagName) ?? ""
            guard let archive = release.assets.first(where: {
                $0.name == "Jarvis-\(versionSuffix)-macos.zip"
            }),
                archive.size > 0,
                archive.size <= JarvisUpdateSecurity.maximumArchiveBytes,
                let digest = archive.digest,
                isAllowedGitHubAssetURL(archive.browserDownloadURL)
            else {
                throw JarvisUpdateError.downloadUnavailable
            }
            releaseInfo = JarvisReleaseInfo(
                version: release.tagName,
                build: nil,
                releaseURL: release.htmlURL,
                downloadURL: archive.browserDownloadURL,
                assetDigest: digest,
                archiveSize: archive.size,
                isLegacyBootstrap: true
            )
        } else {
            throw JarvisUpdateError.missingSignedManifest
        }
        JarvisLog.info(
            category: .update,
            event: "release.check.complete",
            operationID: operationID,
            result: "success",
            fields: [
                "version": releaseInfo.version,
                "hasDownload": String(releaseInfo.downloadURL != nil),
                "hasDigest": String(releaseInfo.assetDigest != nil),
                "legacyBootstrap": String(releaseInfo.isLegacyBootstrap)
            ]
        )
        return releaseInfo
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        JarvisUpdateSecurity.isNewer(
            remoteVersion: remote,
            remoteBuild: nil,
            than: local,
            localBuild: nil
        )
    }

    func isNewer(_ release: JarvisReleaseInfo, than localVersion: String, build localBuild: String) -> Bool {
        JarvisUpdateSecurity.isNewer(
            remoteVersion: release.version,
            remoteBuild: release.build,
            than: localVersion,
            localBuild: localBuild
        )
    }

    /// Downloads and validates an update without terminating the app or
    /// changing privacy permissions. Installation is handed off only after
    /// AppKit confirms that termination has been accepted.
    func prepareUpdate(_ release: JarvisReleaseInfo) async throws -> JarvisStagedUpdate {
        let operationID = JarvisLog.operationID()
        JarvisLog.notice(
            category: .update,
            event: "install.begin",
            operationID: operationID,
            fields: [
                "version": release.version,
                "hasDigest": String(release.assetDigest != nil),
                "legacyBootstrap": String(release.isLegacyBootstrap)
            ]
        )
        defer {
            JarvisLog.notice(
                category: .update,
                event: "install.complete",
                operationID: operationID,
                result: "prepared",
                fields: ["version": release.version]
            )
        }
        guard let downloadURL = release.downloadURL else {
            throw JarvisUpdateError.downloadUnavailable
        }

        // Resolve the writable install location before touching LaunchServices.
        // When macOS runs a quarantined app through App Translocation, the
        // original Downloads path is only discoverable while its registration
        // is still intact.
        let launchedAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard launchedAppURL.pathExtension.lowercased() == "app",
              launchedAppURL.lastPathComponent == "Jarvis.app"
        else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }
        let currentAppURL = try resolveInstallLocation(for: launchedAppURL)
        try validateInstallLocation(currentAppURL)

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("JarvisUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryDirectory.path)
        var preparedSuccessfully = false
        defer {
            if !preparedSuccessfully {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        // URLSession follows the GitHub Release redirect and owns the
        // temporary download file until the request completes.
        var request = URLRequest(url: downloadURL)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (downloadedURL, response) = try await updateSession.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let archiveURL = temporaryDirectory.appendingPathComponent("Jarvis-update.zip")
        let archiveAttributes = try fileManager.attributesOfItem(atPath: downloadedURL.path)
        let downloadedSize = (archiveAttributes[.size] as? NSNumber)?.int64Value ?? -1
        guard downloadedSize == release.archiveSize,
              downloadedSize <= JarvisUpdateSecurity.maximumArchiveBytes
        else {
            throw JarvisUpdateError.invalidArchive
        }
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)
        try verifyDigest(of: archiveURL, expected: release.assetDigest)

        let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try runTool(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
        )

        guard let newAppURL = findApplication(in: extractionDirectory),
              isValidApplicationBundle(newAppURL)
        else {
            throw JarvisUpdateError.invalidApplication
        }

        guard let newAppVersion = Self.bundleValue("CFBundleShortVersionString", in: newAppURL),
              let newAppBuild = Self.bundleValue("CFBundleVersion", in: newAppURL),
              JarvisUpdateSecurity.normalizedVersion(newAppVersion) == JarvisUpdateSecurity.normalizedVersion(release.version),
              release.build == nil || release.build == newAppBuild,
              JarvisUpdateSecurity.isNewer(
                  remoteVersion: newAppVersion,
                  remoteBuild: newAppBuild,
                  than: JarvisAppVersion.shortVersion,
                  localBuild: JarvisAppVersion.build
              )
        else {
            throw JarvisUpdateError.mismatchedVersion
        }

        if JarvisLocalSigning.isAvailable {
            // The download is verified by digest and signature before this
            // point; signing it here keeps the grants that were deliberately
            // not reset above. A failure aborts the update rather than
            // silently installing an app that would lose them.
            try JarvisLocalSigning.resign(appAt: newAppURL)
        }

        let scriptURL = temporaryDirectory.appendingPathComponent("install-update.zsh")
        try makeInstallerScript(
            at: scriptURL,
            currentAppURL: currentAppURL,
            newAppURL: newAppURL,
            temporaryDirectory: temporaryDirectory,
            parentProcessID: ProcessInfo.processInfo.processIdentifier
        )

        try runTool("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", newAppURL.path])
        preparedSuccessfully = true
        JarvisLog.notice(
            category: .update,
            event: "install.prepared",
            operationID: operationID,
            result: "success",
            fields: ["version": release.version]
        )
        return JarvisStagedUpdate(
            version: release.version,
            temporaryDirectoryURL: temporaryDirectory,
            scriptURL: scriptURL
        )
    }

    func launchInstaller(for stagedUpdate: JarvisStagedUpdate) throws {
        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        installer.arguments = ["/bin/zsh", stagedUpdate.scriptURL.path]
        installer.standardOutput = FileHandle.nullDevice
        installer.standardError = FileHandle.nullDevice
        try installer.run()
    }

    static func resetPrivacyPermissions(bundleIdentifier: String) throws {
        try JarvisPrivacyPermissionReset.reset(bundleIdentifier: bundleIdentifier)
    }

    private func downloadSmallAsset(_ asset: GitHubReleaseAsset, maximumBytes: Int) async throws -> Data {
        guard asset.size > 0,
              asset.size <= maximumBytes,
              isAllowedGitHubAssetURL(asset.browserDownloadURL)
        else {
            throw JarvisUpdateError.invalidManifest
        }
        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (fileURL, response) = try await updateSession.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? maximumBytes + 1
        guard size <= maximumBytes, size == asset.size else {
            throw JarvisUpdateError.invalidManifest
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    private func isAllowedGitHubAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com"
    }

    func isLegacyBootstrapRelease(_ version: String) -> Bool {
        JarvisUpdateSecurity.normalizedVersion(version) == Self.legacyBootstrapMaximumVersion
    }

    private static func bundleValue(_ key: String, in appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist[key] as? String
    }

    private func validateInstallLocation(_ appURL: URL) throws {
        let path = appURL.path
        if path.range(of: "/AppTranslocation/", options: .caseInsensitive) != nil {
            throw JarvisUpdateError.unsupportedInstallLocation
        }

        let resourceValues = try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        if resourceValues?.volumeIsReadOnly == true {
            throw JarvisUpdateError.unsupportedInstallLocation
        }
    }

    private func resolveInstallLocation(for launchedURL: URL) throws -> URL {
        guard launchedURL.path.range(of: "/AppTranslocation/", options: .caseInsensitive) != nil else {
            return launchedURL
        }

        let launchedExecutable = launchedURL.appendingPathComponent("Contents/MacOS/Jarvis")
        guard let launchedExecutableDigest = try? sha256(of: launchedExecutable),
              let bundleIdentifier = Bundle.main.bundleIdentifier,
              let unmanagedURLs = LSCopyApplicationURLsForBundleIdentifier(
                  bundleIdentifier as CFString,
                  nil
              )
        else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }

        let registeredURLs = unmanagedURLs.takeRetainedValue() as NSArray
        let candidates = registeredURLs.compactMap { $0 as? URL }
            .map(\.standardizedFileURL)
            .filter { candidate in
                candidate.pathExtension.lowercased() == "app"
                    && candidate.lastPathComponent == "Jarvis.app"
                    && candidate.path.range(of: "/AppTranslocation/", options: .caseInsensitive) == nil
                    && isValidApplicationBundle(candidate)
                    && (try? sha256(of: candidate.appendingPathComponent("Contents/MacOS/Jarvis"))) == launchedExecutableDigest
            }

        guard !candidates.isEmpty else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }
        guard candidates.count == 1 else {
            throw JarvisUpdateError.ambiguousInstallLocation
        }
        return candidates[0]
    }

    func verifyDigest(of fileURL: URL, expected: String?) throws {
        guard let expected, expected.lowercased().hasPrefix("sha256:") else {
            throw JarvisUpdateError.checksumUnavailable
        }

        let digest = try sha256(of: fileURL)
        let expectedDigest = String(expected.dropFirst("sha256:".count))
        guard digest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
            throw JarvisUpdateError.checksumMismatch
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private var updateSession: URLSession {
        Self.updateSession
    }

    private static let updateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 10 * 60
        return URLSession(configuration: configuration)
    }()

    private func findApplication(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app", url.lastPathComponent == "Jarvis.app" {
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
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        else {
            return false
        }
        guard bundleIdentifier == Bundle.main.bundleIdentifier else {
            return false
        }
        return signingTeamIdentifier(of: url) == signingTeamIdentifier(of: Bundle.main.bundleURL)
    }

    func signingTeamIdentifier(of appURL: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let information = information as? [String: Any]
        else {
            return nil
        }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
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
}

extension JarvisUpdateService {
    // Keep the replacement/rollback script as one transaction so that every
    // path shares the same quoting, logging, and recovery behavior.
    // swiftlint:disable:next function_body_length
    func makeInstallerScript(
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
        log_file=\(shellQuote(Self.updateLogURL.path))
        /bin/mkdir -p "$(/usr/bin/dirname "$log_file")" 2>/dev/null || true
        exec >> "$log_file" 2>&1
        log() {
            echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*"
        }

        old_app=\(shellQuote(currentAppURL.path))
        new_app=\(shellQuote(newAppURL.path))
        backup_app=\(shellQuote(backupURL.path))
        temp_dir=\(shellQuote(temporaryDirectory.path))
        parent_pid=\(parentProcessID)

        log "开始安装更新：$new_app -> $old_app"
        log "当前进程 PID：$parent_pid"

        is_app_running() {
            local target="$1"
            /bin/ps -axo pid=,command= \\
                | /usr/bin/grep -F "$target/Contents/MacOS/Jarvis" \\
                | /usr/bin/grep -v -F "/usr/bin/grep" >/dev/null 2>&1
        }

        launch_and_verify() {
            local target="$1"
            local attempt
            local tick
            for attempt in 1 2 3; do
                log "启动应用（第 $attempt 次）：$target"
                if ! /usr/bin/open -na "$target"; then
                    log "open 启动命令失败"
                fi
                for tick in {1..40}; do
                    if is_app_running "$target"; then
                        log "检测到新进程已启动"
                        return 0
                    fi
                    /bin/sleep 0.25
                done
                log "等待应用进程超时"
            done
            return 1
        }

        refresh_launch_services() {
            local target="$1"
            local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if [[ -x "$lsregister" ]]; then
                "$lsregister" -u "$target" >/dev/null 2>&1 || true
                "$lsregister" -f "$target" >/dev/null 2>&1 || log "刷新 LaunchServices 图标注册失败"
            fi
        }

        cleanup_user_owned() {
            /bin/rm -rf "$backup_app" "$temp_dir"
        }

        restore_user_owned() {
            log "回滚到旧版本"
            /bin/rm -rf "$old_app"
            /bin/mv "$backup_app" "$old_app"
        }

        cleanup_with_authorization() {
            /usr/bin/osascript - "$backup_app" "$temp_dir" <<'APPLESCRIPT'
        on run argv
            set backupApp to item 1 of argv
            set tempDir to item 2 of argv
            set command to "/bin/rm -rf " & quoted form of backupApp & " " & quoted form of tempDir
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
        }

        restore_with_authorization() {
            /usr/bin/osascript - "$old_app" "$backup_app" <<'APPLESCRIPT'
        on run argv
            set oldApp to item 1 of argv
            set backupApp to item 2 of argv
            set command to "/bin/rm -rf " & quoted form of oldApp & " && /bin/mv " & quoted form of backupApp & " " & quoted form of oldApp
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
        }

        replace_without_authorization() {
            if ! /bin/mv "$old_app" "$backup_app"; then
                log "普通权限移动旧应用失败"
                return 1
            fi
            log "旧应用已暂存为备份"

            if ! /usr/bin/ditto "$new_app" "$old_app"; then
                log "普通权限复制新应用失败"
                restore_user_owned
                return 1
            fi
            log "新应用已替换到原路径"
            refresh_launch_services "$old_app"

            if launch_and_verify "$old_app"; then
                cleanup_user_owned
                log "更新成功"
                exit 0
            fi

            log "新应用启动失败，执行回滚"
            restore_user_owned
            launch_and_verify "$old_app" || log "旧版本恢复后启动也失败"
            /bin/rm -rf "$temp_dir"
            exit 1
        }

        replace_with_authorization() {
            log "请求系统管理员授权替换应用"
            if ! /usr/bin/osascript - "$old_app" "$new_app" "$backup_app" <<'APPLESCRIPT'
        on run argv
            set oldApp to item 1 of argv
            set newApp to item 2 of argv
            set backupApp to item 3 of argv
            set command to "/bin/mv " & quoted form of oldApp & " " & quoted form of backupApp & " && if /usr/bin/ditto " & quoted form of newApp & " " & quoted form of oldApp & "; then exit 0; else /bin/rm -rf " & quoted form of oldApp & " && /bin/mv " & quoted form of backupApp & " " & quoted form of oldApp & "; exit 1; end if"
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
            then
                log "管理员授权失败或用户取消"
                launch_and_verify "$old_app" || log "授权取消后旧版本启动失败"
                /bin/rm -rf "$temp_dir"
                exit 1
            fi
            log "管理员权限替换完成"
            refresh_launch_services "$old_app"

            if launch_and_verify "$old_app"; then
                cleanup_with_authorization || log "清理备份文件失败：$backup_app"
                log "更新成功"
                exit 0
            fi

            log "新应用启动失败，执行管理员回滚"
            if restore_with_authorization; then
                launch_and_verify "$old_app" || log "旧版本恢复后启动也失败"
            else
                log "管理员回滚失败：$backup_app"
            fi
            /bin/rm -rf "$temp_dir"
            exit 1
        }

        log "等待用户已批准退出的应用结束"
        while /bin/ps -p "$parent_pid" -o command= 2>/dev/null \\
            | /usr/bin/grep -F "$old_app/Contents/MacOS/Jarvis" >/dev/null 2>&1; do
            /bin/sleep 0.1
        done
        log "应用进程已结束，开始替换"

        if /usr/bin/codesign --verify --deep --strict "$new_app" >/dev/null 2>&1; then
            log "新应用签名校验通过"
        else
            log "新应用签名校验失败，保留旧版本并重新启动"
            /usr/bin/open -na "$old_app" || log "旧版本重新启动失败"
            /bin/rm -rf "$temp_dir"
            exit 1
        fi

        # 发布包没有开发者 ID 签名，留着 quarantine 会被 Gatekeeper 挡住启动，
        # 所以只在签名校验通过之后才摘。
        target="$new_app"
        \(JarvisSigningScript.stripQuarantine)

        if replace_without_authorization; then
            exit 0
        fi
        replace_with_authorization
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
