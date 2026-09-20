import AppKit
@testable import Jarvis
import XCTest

@MainActor
final class EntertainmentVideoDownloadTests: XCTestCase {
    func testLinkMatcherAcceptsOfficialWatchAndShortURLs() {
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.youtube.com/watch?v=dQw4w9WgXcQ")?.platform,
            .youtube
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://youtu.be/dQw4w9WgXcQ")?.platform,
            .youtube
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.youtube.com/shorts/abcdef12345")?.platform,
            .youtube
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://x.com/user/status/1234567890")?.platform,
            .x
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://twitter.com/user/status/1234567890")?.platform,
            .x
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.tiktok.com/@user/video/1234567890")?.platform,
            .tiktok
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://vm.tiktok.com/ZMabcdef/")?.platform,
            .tiktok
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.twitch.tv/shroud")?.platform,
            .twitch
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.twitch.tv/videos/123456789")?.platform,
            .twitch
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.twitch.tv/shroud/clip/FunnyClip")?.platform,
            .twitch
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://clips.twitch.tv/FunnyClip")?.platform,
            .twitch
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.bilibili.com/video/BV1xx411c7mD")?.platform,
            .bilibili
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://m.bilibili.com/video/av170001")?.platform,
            .bilibili
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://www.bilibili.com/bangumi/play/ep100000")?.platform,
            .bilibili
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://b23.tv/BV1xx411c7mD")?.platform,
            .bilibili
        )
        XCTAssertEqual(
            EntertainmentVideoLink.match("https://live.bilibili.com/6")?.platform,
            .bilibili
        )
    }

    func testLinkMatcherExtractsURLFromCopiedTextAndRejectsUnrelatedSites() {
        let mixed = "看看这个 https://youtu.be/dQw4w9WgXcQ 挺好看"
        XCTAssertEqual(EntertainmentVideoLink.match(mixed)?.platform, .youtube)
        let xCopiedText = "来自 X 的分享：https://x.com/i/status/1234567890?s=20&t=abc。"
        XCTAssertEqual(
            EntertainmentVideoLink.match(xCopiedText)?.url.absoluteString,
            "https://x.com/i/status/1234567890?s=20&t=abc"
        )
        XCTAssertNil(EntertainmentVideoLink.match("https://example.com/watch?v=abc"))
        XCTAssertNil(EntertainmentVideoLink.match("https://accounts.google.com/"))
        XCTAssertNil(EntertainmentVideoLink.match("not a url"))
        XCTAssertNil(EntertainmentVideoLink.match("https://www.twitch.tv/"))
        XCTAssertNil(EntertainmentVideoLink.match("https://www.twitch.tv/directory/game/Art"))
        XCTAssertNil(EntertainmentVideoLink.match("https://www.bilibili.com/"))
        XCTAssertNil(EntertainmentVideoLink.match("https://space.bilibili.com/2"))
        XCTAssertNil(EntertainmentVideoLink.match("https://search.bilibili.com/all?keyword=test"))
        XCTAssertEqual(
            EntertainmentVideoDownloadError.invalidLink.errorDescription,
            "请粘贴 YouTube、X、TikTok、Twitch 或哔哩哔哩的视频链接"
        )
    }

    func testPreferredURLUsesLatestClipboardLinkBeforePreviousPageURL() {
        let previousURL = URL(string: "https://x.com/old/status/111")
        let latestClipboard = "https://x.com/new/status/222\n"

        XCTAssertEqual(
            EntertainmentVideoLink.preferredURL(
                initialURL: previousURL,
                clipboardText: latestClipboard
            )?.absoluteString,
            "https://x.com/new/status/222"
        )
        XCTAssertEqual(
            EntertainmentVideoLink.preferredURL(
                initialURL: previousURL,
                clipboardText: nil
            ),
            previousURL
        )
    }

    func testQualityBuilderKeepsExactHeightsAndAddsBestAndAudio() {
        let dump = YTDLPDump(
            title: "Demo",
            thumbnail: "https://example.com/thumb.jpg",
            duration: 125,
            formats: [
                YTDLPFormat(formatID: "18", height: 360, ext: "mp4", vcodec: "avc1", acodec: "mp4a", filesize: 1_000_000, filesizeApprox: nil),
                YTDLPFormat(formatID: "22", height: 720, ext: "mp4", vcodec: "avc1", acodec: "mp4a", filesize: 4_000_000, filesizeApprox: nil),
                YTDLPFormat(formatID: "137", height: 1080, ext: "mp4", vcodec: "avc1", acodec: "none", filesize: 8_000_000, filesizeApprox: nil),
                YTDLPFormat(formatID: "140", height: nil, ext: "m4a", vcodec: "none", acodec: "mp4a", filesize: 500_000, filesizeApprox: nil)
            ]
        )

        let options = EntertainmentVideoQualityBuilder.options(from: dump)
        XCTAssertEqual(options.first?.id, "best")
        XCTAssertEqual(options.map(\.title), ["最佳画质", "1080p", "720p", "360p", "仅音频"])
        XCTAssertEqual(options.last?.kind, .audio)
        XCTAssertTrue(options.contains(where: { $0.format.contains("height<=1080") }))
        XCTAssertFalse(options.contains(where: { $0.title == "480p" }))
    }

    func testProgressParserReadsYTDLPPercentLines() throws {
        let percent = try XCTUnwrap(
            EntertainmentVideoDownloadService.progressPercent(
                in: "[download]  12.5% of  10.00MiB at  1.00MiB/s ETA 00:08"
            )
        )
        XCTAssertEqual(percent, 0.125, accuracy: 0.0001)
        XCTAssertNil(EntertainmentVideoDownloadService.progressPercent(in: "[info] downloading"))
    }

    func testFilenameSanitizerRemovesPathCharacters() {
        XCTAssertEqual(
            EntertainmentVideoDownloadService.sanitizedFilename("a/b:c?.mp4", ext: "mp4"),
            "a-b-c.mp4"
        )
        XCTAssertEqual(
            EntertainmentVideoDownloadService.sanitizedFilename("   ", ext: "mp3"),
            "视频.mp3"
        )
    }

    func testLocatorUsesFirstExecutableCandidate() {
        let found = YTDLPLocator.findExecutable(
            fileExists: { $0 == "/usr/local/bin/yt-dlp" },
            pathEnvironment: "/tmp/bin:/usr/bin"
        )
        XCTAssertEqual(found?.path, "/usr/local/bin/yt-dlp")
        XCTAssertNil(
            YTDLPLocator.findExecutable(
                fileExists: { _ in false },
                pathEnvironment: ""
            )
        )
    }

    func testCompletedFileCanBeCopiedToPasteboardAndDuplicated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-video-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("clip.mp4")
        let contents = Data("video".utf8)
        try contents.write(to: source)
        let pasteboard = NSPasteboard.withUniqueName()
        XCTAssertTrue(EntertainmentVideoFileActions.copyFile(source, to: pasteboard))
        XCTAssertEqual(
            pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
            source
        )

        let destination = directory.appendingPathComponent("copy.mp4")
        try EntertainmentVideoFileActions.copyFile(at: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), contents)

        let record = try EntertainmentVideoDownloadRecord(
            id: UUID(),
            platform: .youtube,
            title: "clip",
            qualityTitle: "1080p",
            filename: "clip.mp4",
            sourceURL: XCTUnwrap(URL(string: "https://youtu.be/abc")),
            destinationPath: source.path,
            createdAt: Date(),
            finishedAt: Date(),
            state: .completed,
            errorMessage: nil
        )
        XCTAssertTrue(record.canOpenFile)
        XCTAssertTrue(EntertainmentVideoFileActions.copyFile(record.destinationURL, to: NSPasteboard.withUniqueName()))
    }

    func testDownloadHistoryRecordsNewestFirstAndCapsEntries() {
        let first = sampleRecord(id: UUID(), title: "one")
        let second = sampleRecord(id: UUID(), title: "two")
        let recorded = EntertainmentVideoDownloadHistory.recording(
            second,
            into: EntertainmentVideoDownloadHistory.recording(first, into: [])
        )
        XCTAssertEqual(recorded.map(\.title), ["two", "one"])

        let sameID = sampleRecord(id: first.id, title: "one-updated")
        let replaced = EntertainmentVideoDownloadHistory.recording(sameID, into: recorded)
        XCTAssertEqual(replaced.map(\.title), ["one-updated", "two"])

        var overflow = (1 ... EntertainmentVideoDownloadHistory.maxCount).map {
            sampleRecord(id: UUID(), title: "item-\($0)")
        }
        overflow = EntertainmentVideoDownloadHistory.recording(
            sampleRecord(id: UUID(), title: "newest"),
            into: overflow
        )
        XCTAssertEqual(overflow.first?.title, "newest")
        XCTAssertEqual(overflow.count, EntertainmentVideoDownloadHistory.maxCount)
    }

    func testDownloadHistoryStoreRoundTripsAndRemovesRecords() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-video-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = EntertainmentVideoDownloadHistoryStore(directoryURL: directory)
        let record = sampleRecord(id: UUID(), title: "saved-clip")
        store.save([record])
        XCTAssertEqual(store.load().map(\.title), ["saved-clip"])

        let remaining = EntertainmentVideoDownloadHistory.removing(record.id, from: store.load())
        store.save(remaining)
        XCTAssertTrue(store.load().isEmpty)
    }

    @MainActor
    func testDownloadManagerLoadsAndClearsPersistedHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-video-history-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = EntertainmentVideoDownloadHistoryStore(directoryURL: directory)
        let record = sampleRecord(id: UUID(), title: "Persisted")
        store.save([record])

        let manager = EntertainmentVideoDownloadManager(historyStore: store)
        XCTAssertEqual(manager.history.map(\.title), ["Persisted"])

        try manager.removeFromHistory(XCTUnwrap(manager.history.first))
        XCTAssertTrue(manager.history.isEmpty)
        XCTAssertTrue(store.load().isEmpty)

        store.save([record, sampleRecord(id: UUID(), title: "Other")])
        let reloaded = EntertainmentVideoDownloadManager(historyStore: store)
        XCTAssertEqual(reloaded.history.count, 2)
        reloaded.clearHistory()
        XCTAssertTrue(reloaded.history.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
    }

    private func sampleRecord(id: UUID, title: String) -> EntertainmentVideoDownloadRecord {
        EntertainmentVideoDownloadRecord(
            id: id,
            platform: .youtube,
            title: title,
            qualityTitle: "1080p",
            filename: "\(title).mp4",
            sourceURL: URL(string: "https://youtu.be/\(id.uuidString)")!,
            destinationPath: "/tmp/\(title).mp4",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_100),
            state: .completed,
            errorMessage: nil
        )
    }

    func testDurationFormattingMatchesPlayerStyle() {
        XCTAssertEqual(EntertainmentVideoDownloadView.formatDuration(65), "1:05")
        XCTAssertEqual(EntertainmentVideoDownloadView.formatDuration(3723), "1:02:03")
    }

    func testNetscapeCookieFileUsesTabSeparatedFields() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: ".youtube.com",
            .path: "/",
            .name: "SID",
            .value: "abc",
            .secure: true,
            .expires: Date(timeIntervalSince1970: 1_800_000_000)
        ]))
        let line = NetscapeCookieFile.line(for: cookie)
        XCTAssertTrue(line.contains(".youtube.com"))
        XCTAssertTrue(line.contains("SID"))
        XCTAssertTrue(line.contains("abc"))
        let youtube = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=abc"))
        let tiktok = try XCTUnwrap(URL(string: "https://www.tiktok.com/@u/video/1"))
        XCTAssertTrue(NetscapeCookieFile.isRelevant(cookie, to: youtube))
        XCTAssertFalse(NetscapeCookieFile.isRelevant(cookie, to: tiktok))

        let biliCookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: ".bilibili.com",
            .path: "/",
            .name: "SESSDATA",
            .value: "token"
        ]))
        let biliVideo = try XCTUnwrap(URL(string: "https://www.bilibili.com/video/BV1xx411c7mD"))
        let biliShort = try XCTUnwrap(URL(string: "https://b23.tv/abcdef"))
        XCTAssertTrue(NetscapeCookieFile.isRelevant(biliCookie, to: biliVideo))
        XCTAssertTrue(NetscapeCookieFile.isRelevant(biliCookie, to: biliShort))
        XCTAssertFalse(NetscapeCookieFile.isRelevant(biliCookie, to: youtube))
    }

    func testYTDLPErrorPrefersERRORLineAndMapsYouTubeBotCheck() {
        let output = Data("""
        WARNING: outdated
        ERROR: [youtube] abc: Sign in to confirm you’re not a bot. Use --cookies
        null
        """.utf8)
        XCTAssertTrue(
            YTDLPProcessRunner.errorMessage(from: output).contains("Sign in to confirm")
        )
        XCTAssertEqual(
            EntertainmentVideoDownloadError.failed(
                "ERROR: [youtube] abc: Sign in to confirm you’re not a bot."
            ).localizedDescription,
            "YouTube 需要登录验证。请先在娱乐广场打开并播放该视频，然后再下载。"
        )
    }
}
