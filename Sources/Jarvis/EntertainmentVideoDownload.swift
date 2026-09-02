import AppKit
import Foundation

enum EntertainmentVideoQualityKind: Equatable, Sendable {
    case video
    case audio
}

struct EntertainmentVideoQuality: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let format: String
    let kind: EntertainmentVideoQualityKind
    let extractAudio: Bool
    let height: Int?
}

struct EntertainmentVideoProbe: Equatable, Sendable {
    let url: URL
    let platform: EntertainmentPlatform
    let title: String
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let qualities: [EntertainmentVideoQuality]
}

struct EntertainmentVideoDownloadItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let platform: EntertainmentPlatform
    let title: String
    let qualityTitle: String
    var filename: String
    var state: AIConversationDownloadState
    var progress: Double?
    var destinationURL: URL?
    var errorMessage: String?

    var canOpenFile: Bool {
        guard state == .completed, let destinationURL else { return false }
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }
}

enum EntertainmentVideoDownloadError: LocalizedError, Equatable {
    case missingYTDLP
    case invalidLink
    case noVideo
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingYTDLP:
            "未找到 yt-dlp。请先安装：brew install yt-dlp ffmpeg"
        case .invalidLink:
            "请粘贴 YouTube、X 或 TikTok 的视频链接"
        case .noVideo:
            "没有解析到可下载的视频"
        case let .failed(message):
            message
        }
    }
}

enum YTDLPLocator {
    static let defaultSearchPaths = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp"
    ]

    static func findExecutable(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> URL? {
        var candidates = defaultSearchPaths
        for directory in pathEnvironment.split(separator: ":") {
            candidates.append("\(directory)/yt-dlp")
        }
        var seen: Set<String> = []
        for path in candidates {
            guard seen.insert(path).inserted, fileExists(path) else { continue }
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

enum EntertainmentVideoQualityBuilder {
    static let preferredHeights = [2160, 1440, 1080, 720, 480, 360, 240]

    static func options(from dump: YTDLPDump) -> [EntertainmentVideoQuality] {
        let formats = dump.formats ?? []
        let videoHeights = Set(formats.compactMap { format -> Int? in
            guard format.hasVideo, let height = format.height, height > 0 else { return nil }
            return height
        })

        var options: [EntertainmentVideoQuality] = [
            EntertainmentVideoQuality(
                id: "best",
                title: "最佳画质",
                subtitle: "自动选择可用的最高分辨率",
                format: "bv*+ba/b",
                kind: .video,
                extractAudio: false,
                height: videoHeights.max()
            )
        ]

        for height in preferredHeights where videoHeights.contains(height) {
            options.append(
                EntertainmentVideoQuality(
                    id: "h\(height)",
                    title: "\(height)p",
                    subtitle: sizeSubtitle(height: height, formats: formats) ?? "MP4 · 视频+音频",
                    format: "bv*[height<=\(height)]+ba/b[height<=\(height)]",
                    kind: .video,
                    extractAudio: false,
                    height: height
                )
            )
        }

        if formats.contains(where: \.hasAudio) {
            options.append(
                EntertainmentVideoQuality(
                    id: "audio",
                    title: "仅音频",
                    subtitle: "提取原声，保存为 MP3",
                    format: "ba/b",
                    kind: .audio,
                    extractAudio: true,
                    height: nil
                )
            )
        }

        return options
    }

    private static func sizeSubtitle(height: Int, formats: [YTDLPFormat]) -> String? {
        let video = formats
            .filter { $0.hasVideo && $0.height == height }
            .compactMap(\.byteCount)
            .max()
        let audio = formats
            .filter { $0.hasAudio && !$0.hasVideo }
            .compactMap(\.byteCount)
            .max()
        guard let video else { return nil }
        let total = video + (audio ?? 0)
        return "MP4 · 约 \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }
}

struct YTDLPDump: Decodable, Equatable, Sendable {
    var title: String?
    var thumbnail: String?
    var duration: Double?
    var formats: [YTDLPFormat]?
}

struct YTDLPFormat: Decodable, Equatable, Sendable {
    var formatID: String?
    var height: Int?
    var ext: String?
    var vcodec: String?
    var acodec: String?
    var filesize: Int64?
    var filesizeApprox: Int64?

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case height
        case ext
        case vcodec
        case acodec
        case filesize
        case filesizeApprox = "filesize_approx"
    }

    var hasVideo: Bool {
        guard let vcodec, vcodec != "none" else { return false }
        return true
    }

    var hasAudio: Bool {
        guard let acodec, acodec != "none" else { return false }
        return true
    }

    var byteCount: Int64? {
        filesize ?? filesizeApprox
    }
}

struct EntertainmentVideoDownloadService: Sendable {
    var locateYTDLP: @Sendable () -> URL? = { YTDLPLocator.findExecutable() }

    func probe(url: URL, platform: EntertainmentPlatform) async throws -> EntertainmentVideoProbe {
        let executable = try resolvedYTDLP()
        let data = try await YTDLPProcessRunner.run(
            executable: executable,
            arguments: [
                "-J",
                "--no-playlist",
                "--no-warnings",
                "--skip-download",
                url.absoluteString
            ]
        )
        let dump = try decodeDump(from: data)
        let qualities = EntertainmentVideoQualityBuilder.options(from: dump)
        guard !qualities.isEmpty else { throw EntertainmentVideoDownloadError.noVideo }
        let title = dump.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return EntertainmentVideoProbe(
            url: url,
            platform: platform,
            title: (title?.isEmpty == false ? title : nil) ?? platform.title,
            thumbnailURL: dump.thumbnail.flatMap(URL.init(string:)),
            duration: dump.duration,
            qualities: qualities
        )
    }

    func download(
        url: URL,
        quality: EntertainmentVideoQuality,
        destination: URL,
        onProgress: (@Sendable (Double) -> Void)?,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws {
        let executable = try resolvedYTDLP()
        var arguments = [
            "--no-playlist",
            "--no-warnings",
            "--newline",
            "--progress",
            "-f", quality.format,
            "-o", destination.path,
            "--merge-output-format", "mp4"
        ]
        if quality.extractAudio {
            arguments.append(contentsOf: ["-x", "--audio-format", "mp3"])
        }
        arguments.append(url.absoluteString)
        _ = try await YTDLPProcessRunner.run(
            executable: executable,
            arguments: arguments,
            onLine: { line in
                if let percent = Self.progressPercent(in: line) {
                    onProgress?(percent)
                }
            },
            isCancelled: isCancelled
        )
    }

    static func progressPercent(in line: String) -> Double? {
        guard let range = line.range(of: #"\[download\]\s+(\d+(?:\.\d+)?)%"#, options: .regularExpression) else {
            return nil
        }
        let snippet = String(line[range])
        let digits = snippet.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    static func sanitizedFilename(_ title: String, ext: String) -> String {
        let stripped = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .components(separatedBy: CharacterSet(charactersIn: "\\?%*|\"<>"))
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var base = stripped.isEmpty ? "视频" : String(stripped.prefix(80))
        let suffix = ".\(ext)"
        if base.lowercased().hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        return "\(base)\(suffix)"
    }

    private func resolvedYTDLP() throws -> URL {
        guard let executable = locateYTDLP() else {
            throw EntertainmentVideoDownloadError.missingYTDLP
        }
        return executable
    }

    private func decodeDump(from data: Data) throws -> YTDLPDump {
        let trimmed = data.trimmingJSONObject()
        do {
            return try JSONDecoder().decode(YTDLPDump.self, from: trimmed)
        } catch {
            if let text = String(data: data, encoding: .utf8),
               let message = text.split(separator: "\n").last,
               !message.isEmpty
            {
                throw EntertainmentVideoDownloadError.failed(String(message))
            }
            throw EntertainmentVideoDownloadError.failed("无法解析视频信息")
        }
    }
}

enum YTDLPProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        onLine: (@Sendable (String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try runBlocking(
                        executable: executable,
                        arguments: arguments,
                        onLine: onLine,
                        isCancelled: isCancelled
                    )
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executable: URL,
        arguments: [String],
        onLine: (@Sendable (String) -> Void)?,
        isCancelled: (@Sendable () -> Bool)?
    ) throws -> Data {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(extraPath):\(path)"
        } else {
            environment["PATH"] = extraPath
        }
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        var collected = Data()
        var pending = Data()
        let lock = NSLock()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            lock.lock()
            collected.append(chunk)
            emitLines(from: chunk, pending: &pending, onLine: onLine)
            lock.unlock()
            if isCancelled?() == true, process.isRunning {
                process.terminate()
            }
        }

        try process.run()
        while process.isRunning {
            if isCancelled?() == true {
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        output.fileHandleForReading.readabilityHandler = nil
        let remainder = output.fileHandleForReading.readDataToEndOfFile()
        if !remainder.isEmpty {
            lock.lock()
            collected.append(remainder)
            lock.unlock()
        }
        process.waitUntilExit()

        if isCancelled?() == true {
            throw CancellationError()
        }
        if process.terminationStatus != 0 {
            let text = String(data: collected, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = text.split(separator: "\n").last.map(String.init) ?? "yt-dlp 下载失败"
            throw EntertainmentVideoDownloadError.failed(message)
        }
        return collected
    }

    private static func emitLines(
        from chunk: Data,
        pending: inout Data,
        onLine: (@Sendable (String) -> Void)?
    ) {
        pending.append(chunk)
        let lines = pending.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if let last = lines.last, last.isEmpty == false, pending.last != UInt8(ascii: "\n") {
            pending = Data(last)
            for line in lines.dropLast() {
                if let text = String(data: Data(line), encoding: .utf8) {
                    onLine?(text)
                }
            }
            return
        }
        pending.removeAll()
        for line in lines where !line.isEmpty {
            if let text = String(data: Data(line), encoding: .utf8) {
                onLine?(text)
            }
        }
    }
}

private extension Data {
    func trimmingJSONObject() -> Data {
        guard let text = String(data: self, encoding: .utf8) else { return self }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end
        else {
            return self
        }
        return Data(text[start ... end].utf8)
    }
}

@MainActor
final class EntertainmentVideoDownloadManager: ObservableObject {
    @Published private(set) var items: [EntertainmentVideoDownloadItem] = []

    private let service: EntertainmentVideoDownloadService
    private let cancellation = EntertainmentDownloadCancellation()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(service: EntertainmentVideoDownloadService = EntertainmentVideoDownloadService()) {
        self.service = service
    }

    var activeCount: Int {
        items.count(where: { $0.state.isActive })
    }

    var hasDownloads: Bool {
        !items.isEmpty
    }

    var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    func probe(urlText: String) async throws -> EntertainmentVideoProbe {
        guard let match = EntertainmentVideoLink.match(urlText) else {
            throw EntertainmentVideoDownloadError.invalidLink
        }
        return try await service.probe(url: match.url, platform: match.platform)
    }

    func download(probe: EntertainmentVideoProbe, quality: EntertainmentVideoQuality) {
        let ext = quality.extractAudio ? "mp3" : "mp4"
        let filename = EntertainmentVideoDownloadService.sanitizedFilename(probe.title, ext: ext)
        let destination = AIConversationDownloadFileName.destination(
            in: downloadsDirectory,
            suggestedFilename: filename
        )
        let id = UUID()
        let item = EntertainmentVideoDownloadItem(
            id: id,
            platform: probe.platform,
            title: probe.title,
            qualityTitle: quality.title,
            filename: destination.lastPathComponent,
            state: .queued,
            progress: 0,
            destinationURL: destination,
            errorMessage: nil
        )
        items.insert(item, at: 0)
        cancellation.reset(id)

        tasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(
                id: id,
                url: probe.url,
                quality: quality,
                destination: destination
            )
        }
    }

    func cancel(_ item: EntertainmentVideoDownloadItem) {
        cancellation.cancel(item.id)
        tasks[item.id]?.cancel()
        updateItem(item.id) {
            if $0.state.isActive {
                $0.state = .cancelled
                $0.errorMessage = nil
            }
        }
    }

    func clearFinished() {
        let active = Set(items.filter(\.state.isActive).map(\.id))
        items.removeAll { !active.contains($0.id) }
    }

    func open(_ item: EntertainmentVideoDownloadItem) {
        guard let destinationURL = item.destinationURL else { return }
        NSWorkspace.shared.open(destinationURL)
    }

    func revealInFinder(_ item: EntertainmentVideoDownloadItem) {
        guard let destinationURL = item.destinationURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    func openDownloadsFolder() {
        NSWorkspace.shared.open(downloadsDirectory)
    }

    private func performDownload(
        id: UUID,
        url: URL,
        quality: EntertainmentVideoQuality,
        destination: URL
    ) async {
        updateItem(id) { $0.state = .downloading }
        do {
            try await service.download(
                url: url,
                quality: quality,
                destination: destination,
                onProgress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.updateItem(id) { $0.progress = progress }
                    }
                },
                isCancelled: { [cancellation] in
                    cancellation.isCancelled(id)
                }
            )
            if cancellation.isCancelled(id) {
                updateItem(id) { $0.state = .cancelled }
                return
            }
            updateItem(id) {
                $0.state = .completed
                $0.progress = 1
                $0.destinationURL = destination
            }
        } catch is CancellationError {
            updateItem(id) { $0.state = .cancelled }
        } catch {
            updateItem(id) {
                $0.state = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
        tasks[id] = nil
    }

    private func updateItem(_ id: UUID, _ update: (inout EntertainmentVideoDownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        update(&items[index])
    }
}

final class EntertainmentDownloadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<UUID> = []

    func cancel(_ id: UUID) {
        lock.lock()
        ids.insert(id)
        lock.unlock()
    }

    func reset(_ id: UUID) {
        lock.lock()
        ids.remove(id)
        lock.unlock()
    }

    func isCancelled(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }
}
