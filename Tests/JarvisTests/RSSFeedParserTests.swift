import Foundation
@testable import Jarvis
import XCTest

/// 脏 feed 样本。真实世界的订阅源全靠这些边角撑着，所以它们以字面量固化在这里，
/// 而不是依赖外部文件——测试不需要额外的资源打包步骤。
enum RSSFeedFixtures {
    static let rss2Basic = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>示例博客</title>
        <link>https://example.com</link>
        <description>一个示例</description>
        <item>
          <title>第一篇文章</title>
          <link>https://example.com/posts/1</link>
          <guid isPermaLink="false">post-1</guid>
          <pubDate>Mon, 15 Sep 2026 08:30:00 +0800</pubDate>
          <author>someone@example.com (张三)</author>
          <description>摘要内容</description>
        </item>
        <item>
          <title>第二篇文章</title>
          <link>https://example.com/posts/2</link>
          <description><![CDATA[<p>正文里的 <strong>HTML</strong></p>]]></description>
        </item>
      </channel>
    </rss>
    """

    static let atom = """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Atom 示例</title>
      <link href="https://atom.example.com/" rel="alternate"/>
      <icon>https://atom.example.com/icon.png</icon>
      <entry>
        <title>Atom 条目</title>
        <link href="https://atom.example.com/entry/1" rel="alternate"/>
        <id>tag:atom.example.com,2026:1</id>
        <published>2026-09-15T08:30:00Z</published>
        <updated>2026-09-16T09:00:00Z</updated>
        <author><name>李四</name></author>
        <summary>摘要</summary>
        <content type="html">&lt;p&gt;全文&lt;/p&gt;</content>
      </entry>
    </feed>
    """

    static let rss1RDF = """
    <?xml version="1.0"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns="http://purl.org/rss/1.0/"
             xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://rdf.example.com/">
        <title>RDF 示例</title>
        <link>https://rdf.example.com/</link>
      </channel>
      <item rdf:about="https://rdf.example.com/a">
        <title>RDF 条目</title>
        <link>https://rdf.example.com/a</link>
        <dc:date>2026-09-15T08:30:00+08:00</dc:date>
        <dc:creator>王五</dc:creator>
      </item>
    </rdf:RDF>
    """

    static let namespacesAndCDATA = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"
         xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>命名空间示例</title>
        <link>https://ns.example.com</link>
        <item>
          <title>带全文的条目</title>
          <link>https://ns.example.com/full</link>
          <dc:creator>赵六</dc:creator>
          <content:encoded><![CDATA[<div><p>第一段</p><p>第二段</p></div>]]></content:encoded>
        </item>
      </channel>
    </rss>
    """

    static let relativeLinks = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>相对链接</title>
        <link>/blog</link>
        <item>
          <title>相对链接条目</title>
          <link>/blog/posts/9</link>
        </item>
      </channel>
    </rss>
    """

    static let brokenDates = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>日期很乱</title>
        <link>https://dates.example.com</link>
        <item>
          <title>日期非法</title>
          <link>https://dates.example.com/1</link>
          <pubDate>昨天下午</pubDate>
        </item>
        <item>
          <title>日期是另一种格式</title>
          <link>https://dates.example.com/2</link>
          <pubDate>2026-09-15 08:30:00</pubDate>
        </item>
      </channel>
    </rss>
    """

    static let emptyChannel = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel><title>空订阅</title><link>https://empty.example.com</link></channel></rss>
    """

    static let malformed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0"><channel><title>没关标签</title>
    """

    static let notAFeed = """
    <html><head><title>只是一个网页</title></head><body>hello</body></html>
    """

    /// 不声明编码的 GBK feed：老中文博客的典型形态。
    static var gbkWithoutDeclaration: Data {
        let xml = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel>
        <title>中文订阅源</title>
        <link>https://gbk.example.com</link>
        <item><title>中文条目标题</title><link>https://gbk.example.com/1</link></item>
        </channel></rss>
        """
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        return xml.data(using: encoding) ?? Data()
    }

    static var withBOM: Data {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(rss2Basic.utf8))
        return data
    }
}

final class RSSFeedParserTests: XCTestCase {
    func testParsesRSS2ChannelAndEntries() throws {
        let feed = try RSSFeedParser.parse(Data(RSSFeedFixtures.rss2Basic.utf8))

        XCTAssertEqual(feed.title, "示例博客")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://example.com")
        XCTAssertEqual(feed.entries.count, 2)

        let first = try XCTUnwrap(feed.entries.first)
        XCTAssertEqual(first.title, "第一篇文章")
        XCTAssertEqual(first.guid, "post-1")
        XCTAssertEqual(first.link?.absoluteString, "https://example.com/posts/1")
        XCTAssertEqual(first.summaryHTML, "摘要内容")
        XCTAssertNotNil(first.publishedAt)
        XCTAssertEqual(first.author, "someone@example.com (张三)")
    }

    func testParsesAtomWithAttributesAndNamespacedContent() throws {
        let feed = try RSSFeedParser.parse(Data(RSSFeedFixtures.atom.utf8))

        XCTAssertEqual(feed.title, "Atom 示例")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://atom.example.com/")
        XCTAssertEqual(feed.iconURL?.absoluteString, "https://atom.example.com/icon.png")

        let entry = try XCTUnwrap(feed.entries.first)
        XCTAssertEqual(entry.title, "Atom 条目")
        XCTAssertEqual(entry.guid, "tag:atom.example.com,2026:1")
        XCTAssertEqual(entry.link?.absoluteString, "https://atom.example.com/entry/1")
        XCTAssertEqual(entry.author, "李四")
        XCTAssertEqual(entry.summaryHTML, "摘要")
        XCTAssertEqual(entry.contentHTML, "<p>全文</p>")
        XCTAssertNotNil(entry.publishedAt)
    }

    func testParsesRSS1ItemsAtRootLevel() throws {
        let feed = try RSSFeedParser.parse(Data(RSSFeedFixtures.rss1RDF.utf8))

        XCTAssertEqual(feed.title, "RDF 示例")
        let entry = try XCTUnwrap(feed.entries.first)
        XCTAssertEqual(entry.title, "RDF 条目")
        XCTAssertEqual(entry.guid, "https://rdf.example.com/a")
        XCTAssertEqual(entry.author, "王五")
        XCTAssertNotNil(entry.publishedAt)
    }

    func testKeepsCDATABodyAndNamespacePrefixedFields() throws {
        let feed = try RSSFeedParser.parse(Data(RSSFeedFixtures.namespacesAndCDATA.utf8))

        let entry = try XCTUnwrap(feed.entries.first)
        XCTAssertEqual(entry.author, "赵六")
        let content = try XCTUnwrap(entry.contentHTML)
        XCTAssertTrue(content.contains("<p>第一段</p>"))
        XCTAssertTrue(content.contains("<p>第二段</p>"))
    }

    func testResolvesRelativeLinksAgainstFeedURL() throws {
        let feed = try RSSFeedParser.parse(
            Data(RSSFeedFixtures.relativeLinks.utf8),
            baseURL: URL(string: "https://relative.example.com/feed.xml")
        )

        XCTAssertEqual(feed.siteURL?.absoluteString, "https://relative.example.com/blog")
        XCTAssertEqual(
            feed.entries.first?.link?.absoluteString,
            "https://relative.example.com/blog/posts/9"
        )
    }

    /// 认不出的日期只是不填，条目不能丢。
    func testKeepsEntriesWhoseDatesCannotBeParsed() throws {
        let feed = try RSSFeedParser.parse(Data(RSSFeedFixtures.brokenDates.utf8))

        XCTAssertEqual(feed.entries.count, 2)
        XCTAssertNil(feed.entries[0].publishedAt)
        XCTAssertNotNil(feed.entries[1].publishedAt)
    }

    func testParsesEmptyChannelWithoutEntries() throws {
        let feed = try RSSFeedParser.parse(Data(RSSFeedFixtures.emptyChannel.utf8))
        XCTAssertEqual(feed.title, "空订阅")
        XCTAssertTrue(feed.entries.isEmpty)
    }

    func testDecodesGBKFeedWithoutDeclaration() throws {
        let feed = try RSSFeedParser.parse(RSSFeedFixtures.gbkWithoutDeclaration)
        XCTAssertEqual(feed.title, "中文订阅源")
        XCTAssertEqual(feed.entries.first?.title, "中文条目标题")
    }

    func testDecodesUTF8WithByteOrderMark() throws {
        let feed = try RSSFeedParser.parse(RSSFeedFixtures.withBOM)
        XCTAssertEqual(feed.title, "示例博客")
        XCTAssertEqual(feed.entries.count, 2)
    }

    func testRejectsHTMLPage() {
        XCTAssertThrowsError(try RSSFeedParser.parse(Data(RSSFeedFixtures.notAFeed.utf8))) { error in
            XCTAssertEqual(error as? RSSFeedParserError, .notAFeed)
        }
    }

    func testReportsMalformedXML() {
        XCTAssertThrowsError(try RSSFeedParser.parse(Data(RSSFeedFixtures.malformed.utf8))) { error in
            guard case .malformedXML = error as? RSSFeedParserError else {
                return XCTFail("期望 malformedXML，实际 \(error)")
            }
        }
    }

    func testLookalikeProbeAcceptsFeedsAndRejectsPages() {
        XCTAssertTrue(RSSFeedParser.looksLikeFeed(Data(RSSFeedFixtures.rss2Basic.utf8)))
        XCTAssertTrue(RSSFeedParser.looksLikeFeed(Data(RSSFeedFixtures.atom.utf8)))
        XCTAssertFalse(RSSFeedParser.looksLikeFeed(Data(RSSFeedFixtures.notAFeed.utf8)))
    }

    /// 聚合站点的 `<source><title>` 和播客的 `<itunes:title>` 都在更深一层，
    /// 不按层深过滤就会把条目标题覆盖成来源站的名字。
    func testNestedSourceTitleDoesNotOverrideEntryTitle() throws {
        let atomWithSource = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>聚合站</title>
          <entry>
            <title>真正的标题</title>
            <link href="https://example.com/1"/>
            <id>tag:example.com,2026:1</id>
            <source><title>来源站点</title></source>
          </entry>
        </feed>
        """

        let feed = try RSSFeedParser.parse(Data(atomWithSource.utf8))
        XCTAssertEqual(feed.entries.first?.title, "真正的标题")
    }

    func testPodcastNamespacedTitleDoesNotOverrideEntryTitle() throws {
        let rssWithItunesTitle = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
          <channel>
            <title>播客</title>
            <link>https://podcast.example.com</link>
            <item>
              <title>本期节目</title>
              <link>https://podcast.example.com/1</link>
              <itunes:title>iTunes 里的标题</itunes:title>
            </item>
          </channel>
        </rss>
        """

        let feed = try RSSFeedParser.parse(Data(rssWithItunesTitle.utf8))
        XCTAssertEqual(feed.entries.first?.title, "本期节目")
    }

    func testParsesRFC822AndISODatesEqually() {
        XCTAssertNotNil(RSSDateParser.parse("Mon, 15 Sep 2026 08:30:00 +0800"))
        XCTAssertNotNil(RSSDateParser.parse("2026-09-15T08:30:00+08:00"))
        XCTAssertNotNil(RSSDateParser.parse("2026-09-15"))
        XCTAssertNil(RSSDateParser.parse("昨天下午"))
        XCTAssertNil(RSSDateParser.parse(nil))
    }
}
