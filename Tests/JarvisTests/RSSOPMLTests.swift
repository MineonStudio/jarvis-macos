import Foundation
@testable import Jarvis
import XCTest

final class RSSOPMLTests: XCTestCase {
    private let opml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head><title>订阅</title></head>
      <body>
        <outline text="技术" title="技术">
          <outline type="rss" text="示例博客" xmlUrl="https://example.com/feed" htmlUrl="https://example.com"/>
          <outline type="rss" text="另一个" xmlUrl="https://other.example.com/rss"/>
        </outline>
        <outline type="rss" text="独立的" xmlUrl="https://solo.example.com/atom.xml"/>
        <outline type="rss" text="重复的" xmlUrl="https://example.com/feed"/>
        <outline type="rss" text="非法协议" xmlUrl="ftp://files.example.com/feed"/>
      </body>
    </opml>
    """

    func testImportsGroupsAndFeeds() throws {
        let result = try RSSOPML.importFeeds(from: Data(opml.utf8))

        XCTAssertEqual(result.feeds.count, 3)
        XCTAssertEqual(result.duplicateCount, 1)
        XCTAssertEqual(
            result.feeds.map(\.feedURL.absoluteString),
            [
                "https://example.com/feed",
                "https://other.example.com/rss",
                "https://solo.example.com/atom.xml"
            ]
        )
        XCTAssertEqual(result.feeds[0].groupTitle, "技术")
        XCTAssertEqual(result.feeds[1].groupTitle, "技术")
        XCTAssertNil(result.feeds[2].groupTitle)
        XCTAssertEqual(result.feeds[0].siteURL?.absoluteString, "https://example.com")
    }

    func testRejectsNonOPMLPayloads() {
        XCTAssertThrowsError(try RSSOPML.importFeeds(from: Data("<html></html>".utf8)))
    }

    func testExportRoundTripsThroughImport() throws {
        let group = RSSGroup(title: "技术", order: 0)
        let feeds = try [
            RSSFeed(
                title: "示例 & 博客",
                feedURL: XCTUnwrap(URL(string: "https://example.com/feed?a=1&b=2")),
                siteURL: XCTUnwrap(URL(string: "https://example.com")),
                groupID: group.id
            ),
            RSSFeed(title: "独立", feedURL: XCTUnwrap(URL(string: "https://solo.example.com/rss")))
        ]

        let document = RSSOPML.export(feeds: feeds, groups: [group])
        XCTAssertTrue(document.hasPrefix("<?xml"))
        XCTAssertTrue(document.contains("&amp;"))

        let imported = try RSSOPML.importFeeds(from: Data(document.utf8))
        XCTAssertEqual(imported.feeds.count, 2)
        XCTAssertEqual(imported.feeds[0].title, "示例 & 博客")
        XCTAssertEqual(imported.feeds[0].feedURL.absoluteString, "https://example.com/feed?a=1&b=2")
        XCTAssertEqual(imported.feeds[0].groupTitle, "技术")
        XCTAssertNil(imported.feeds[1].groupTitle)
    }

    func testExportEscapesXMLSensitiveCharacters() throws {
        let feed = try RSSFeed(title: "A <b>\"引号\"</b>", feedURL: XCTUnwrap(URL(string: "https://example.com/f")))
        let document = RSSOPML.export(feeds: [feed], groups: [])

        XCTAssertFalse(document.contains("A <b>"))
        XCTAssertTrue(document.contains("A &lt;b&gt;"))
    }
}
