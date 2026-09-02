import AppKit
@testable import Jarvis
import XCTest

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
    }

    func testLinkMatcherExtractsURLFromCopiedTextAndRejectsUnrelatedSites() {
        let mixed = "看看这个 https://youtu.be/dQw4w9WgXcQ 挺好看"
        XCTAssertEqual(EntertainmentVideoLink.match(mixed)?.platform, .youtube)
        XCTAssertNil(EntertainmentVideoLink.match("https://example.com/watch?v=abc"))
        XCTAssertNil(EntertainmentVideoLink.match("https://accounts.google.com/"))
        XCTAssertNil(EntertainmentVideoLink.match("not a url"))
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
