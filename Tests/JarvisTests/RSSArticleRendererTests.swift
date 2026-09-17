import Foundation
@testable import Jarvis
import XCTest

final class RSSArticleRendererTests: XCTestCase {
    /// 危险内容连同它的正文一起丢掉，而不是原样渲染出来。
    func testDropsScriptStyleAndIframeContent() {
        let html = """
        <p>正文之前</p>
        <script>alert('xss')</script>
        <style>.a { color: red }</style>
        <iframe src="https://evil.example.com"></iframe>
        <p>正文之后</p>
        """

        let text = RSSArticleRenderer.plainText(fromHTML: html)

        XCTAssertTrue(text.contains("正文之前"))
        XCTAssertTrue(text.contains("正文之后"))
        XCTAssertFalse(text.contains("alert"))
        XCTAssertFalse(text.contains("color: red"))
        XCTAssertFalse(text.contains("evil.example.com"))
    }

    func testDecodesNamedAndNumericEntities() {
        let html = "<p>A&amp;B &lt;tag&gt; &#65; &#x42; &nbsp;&mdash;&hellip;</p>"
        let text = RSSArticleRenderer.plainText(fromHTML: html)

        XCTAssertTrue(text.contains("A&B"))
        XCTAssertTrue(text.contains("<tag>"))
        XCTAssertTrue(text.contains("A B"))
        XCTAssertTrue(text.contains("—…"))
    }

    func testPlainTextCollapsesWhitespaceAndSeparatesBlocks() {
        let html = "<p>第一段\n   有换行</p><p>第二段</p>"
        let text = RSSArticleRenderer.plainText(fromHTML: html)

        XCTAssertEqual(text, "第一段 有换行\n第二段")
    }

    func testPreviewTextTruncatesWithEllipsis() {
        let html = "<p>" + String(repeating: "字", count: 300) + "</p>"
        let preview = RSSArticleRenderer.previewText(fromHTML: html, limit: 50)

        XCTAssertEqual(preview.count, 51)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testListItemsGetMarkersInPlainTextOrder() throws {
        let html = "<ul><li>苹果</li><li>香蕉</li></ul><ol><li>第一</li></ol>"
        let text = RSSArticleRenderer.plainText(fromHTML: html)

        XCTAssertTrue(text.contains("苹果"))
        XCTAssertTrue(text.contains("香蕉"))
        XCTAssertTrue(text.contains("第一"))
        // 顺序不能乱：列表项的文本必须落在对应位置。
        XCTAssertLessThan(
            try XCTUnwrap(text.range(of: "苹果")?.lowerBound),
            try XCTUnwrap(text.range(of: "香蕉")?.lowerBound)
        )
    }

    func testAttributedStringLinksCarryURLAndStyle() {
        let html = #"<p>看 <a href="https://example.com/post">这篇</a> 文章</p>"#
        let attributed = RSSArticleRenderer.attributedString(fromHTML: html)

        let text = String(attributed.characters)
        XCTAssertTrue(text.contains("这篇"))

        var foundLink: URL?
        for run in attributed.runs where run.link != nil {
            foundLink = run.link
        }
        XCTAssertEqual(foundLink?.absoluteString, "https://example.com/post")
    }

    func testRelativeLinksResolveAgainstBaseURL() {
        let html = #"<a href="/post/1">链接</a>"#
        let attributed = RSSArticleRenderer.attributedString(
            fromHTML: html,
            baseURL: URL(string: "https://example.com/blog/")
        )

        let links = attributed.runs.compactMap(\.link)
        XCTAssertEqual(links.first?.absoluteString, "https://example.com/post/1")
    }

    func testJavascriptSchemeIsNotTurnedIntoALink() {
        let html = #"<a href="javascript:alert(1)">点我</a>"#
        let attributed = RSSArticleRenderer.attributedString(fromHTML: html)

        XCTAssertTrue(attributed.runs.allSatisfy { $0.link == nil })
        XCTAssertTrue(String(attributed.characters).contains("点我"))
    }

    func testImageURLsAreExtractedAndResolved() {
        let html = """
        <img src="https://cdn.example.com/a.jpg">
        <img src="/images/b.png">
        <img src="data:image/png;base64,AAAA">
        <img src="https://cdn.example.com/a.jpg">
        """

        let urls = RSSArticleRenderer.imageURLs(
            inHTML: html,
            baseURL: URL(string: "https://example.com/post")
        )

        XCTAssertEqual(
            urls.map(\.absoluteString),
            ["https://cdn.example.com/a.jpg", "https://example.com/images/b.png"]
        )
    }

    func testUnclosedTagsDoNotSwallowFollowingContent() {
        let html = "<p>没有闭合的段落<div>后面的内容还在"
        let text = RSSArticleRenderer.plainText(fromHTML: html)

        XCTAssertTrue(text.contains("没有闭合的段落"))
        XCTAssertTrue(text.contains("后面的内容还在"))
    }

    func testTokenizerHandlesAngleBracketsInsideAttributes() {
        let html = #"<a title="a > b" href="https://example.com/x">链接</a><p>后面</p>"#
        let text = RSSArticleRenderer.plainText(fromHTML: html)

        XCTAssertTrue(text.contains("链接"))
        XCTAssertTrue(text.contains("后面"))
    }

    func testPreformattedBlocksKeepWhitespace() {
        let html = "<pre>line1\n    indented\nline3</pre>"
        let attributed = RSSArticleRenderer.attributedString(fromHTML: html)
        let text = String(attributed.characters)

        XCTAssertTrue(text.contains("line1\n    indented\nline3"))
    }

    func testUnknownTagsDegradeToPlainText() {
        let html = "<custom-tag>内容仍在</custom-tag>"
        XCTAssertTrue(RSSArticleRenderer.plainText(fromHTML: html).contains("内容仍在"))
    }
}
