import Foundation
@testable import Jarvis
import XCTest

/// 用 URLProtocol 桩住在会话层，测试既不碰真实网络，也能覆盖 304 / 状态码 / 体积
/// 这些分支。
final class RSSStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class RSSFeedClientTests: XCTestCase {
    override func tearDown() {
        RSSStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient() -> RSSFeedClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RSSStubURLProtocol.self]
        return RSSFeedClient(session: URLSession(configuration: configuration), userAgent: "JarvisTest/1.0")
    }

    private static func response(for request: URLRequest, status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func testConditionalRequestHeadersAreSent() throws {
        let request = try RSSFetchRequest(
            url: XCTUnwrap(URL(string: "https://example.com/feed")),
            etag: "W/\"abc\"",
            lastModified: "Mon, 15 Sep 2026 08:30:00 GMT"
        ).urlRequest(userAgent: "JarvisTest/1.0")

        XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "W/\"abc\"")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "If-Modified-Since"),
            "Mon, 15 Sep 2026 08:30:00 GMT"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "JarvisTest/1.0")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("application/rss+xml") == true)
    }

    func testOmittedValidatorsDoNotSendConditionalHeaders() throws {
        let request = try RSSFetchRequest(url: XCTUnwrap(URL(string: "https://example.com/feed")))
            .urlRequest(userAgent: "JarvisTest/1.0")

        XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
    }

    func testFetchReturnsBodyAndValidators() async throws {
        RSSStubURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["ETag": "\"v2\"", "Last-Modified": "Tue, 16 Sep 2026 10:00:00 GMT"]
                )!,
                Data("<rss/>".utf8)
            )
        }

        let response = try await makeClient().fetch(
            RSSFetchRequest(url: XCTUnwrap(URL(string: "https://example.com/feed")))
        )

        XCTAssertFalse(response.notModified)
        XCTAssertEqual(String(data: response.data, encoding: .utf8), "<rss/>")
        XCTAssertEqual(response.etag, "\"v2\"")
        XCTAssertEqual(response.lastModified, "Tue, 16 Sep 2026 10:00:00 GMT")
    }

    func testNotModifiedShortCircuits() async throws {
        RSSStubURLProtocol.handler = { request in
            (Self.response(for: request, status: 304), Data())
        }

        let response = try await makeClient().fetch(
            RSSFetchRequest(url: XCTUnwrap(URL(string: "https://example.com/feed")), etag: "\"v1\"")
        )

        XCTAssertTrue(response.notModified)
        // 服务端没回 ETag 时沿用本地保存的那个，条件请求下一轮仍然成立。
        XCTAssertEqual(response.etag, "\"v1\"")
    }

    func testHTTPFailureSurfacesStatusCode() async throws {
        RSSStubURLProtocol.handler = { request in
            (Self.response(for: request, status: 503), Data())
        }

        do {
            _ = try await makeClient().fetch(RSSFetchRequest(url: XCTUnwrap(URL(string: "https://example.com/feed"))))
            XCTFail("应当抛出状态码错误")
        } catch {
            XCTAssertEqual(error as? RSSFeedClientError, .httpStatus(503))
        }
    }

    func testOversizedResponsesAreRejected() async throws {
        RSSStubURLProtocol.handler = { request in
            (Self.response(for: request, status: 200), Data(repeating: 0x41, count: RSSFeedClient.maximumResponseBytes + 1))
        }

        do {
            _ = try await makeClient().fetch(RSSFetchRequest(url: XCTUnwrap(URL(string: "https://example.com/feed"))))
            XCTFail("应当拒绝超大响应")
        } catch {
            XCTAssertEqual(error as? RSSFeedClientError, .responseTooLarge)
        }
    }
}

final class RSSFeedDiscoveryTests: XCTestCase {
    func testFindsFeedLinksInHTML() throws {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="RSS" href="https://blog.example.com/feed.xml">
        <link rel="alternate" type="application/atom+xml" href="/atom.xml">
        <link rel="stylesheet" href="/style.css">
        <link rel="icon" type="image/png" href="/favicon.png">
        </head><body></body></html>
        """

        let urls = try RSSFeedDiscovery.feedURLs(
            inHTML: html,
            baseURL: XCTUnwrap(URL(string: "https://blog.example.com/"))
        )

        XCTAssertEqual(
            urls.map(\.absoluteString),
            ["https://blog.example.com/feed.xml", "https://blog.example.com/atom.xml"]
        )
    }

    func testIgnoresNonFeedAndDuplicateLinks() throws {
        let html = """
        <link rel="alternate" type="application/rss+xml" href="https://a.example.com/feed">
        <link rel="preload" type="application/rss+xml" href="https://a.example.com/other">
        <link rel="alternate" type="text/html" href="https://a.example.com/page">
        <link rel="alternate" type="application/rss+xml" href="https://a.example.com/feed">
        """

        let urls = try RSSFeedDiscovery.feedURLs(inHTML: html, baseURL: XCTUnwrap(URL(string: "https://a.example.com/")))
        XCTAssertEqual(urls.map(\.absoluteString), ["https://a.example.com/feed"])
    }

    func testAcceptsSingleQuotedAndUppercaseAttributes() throws {
        let html = "<LINK REL='alternate' TYPE='application/rss+xml' HREF='https://b.example.com/rss'>"
        let urls = try RSSFeedDiscovery.feedURLs(inHTML: html, baseURL: XCTUnwrap(URL(string: "https://b.example.com/")))
        XCTAssertEqual(urls.map(\.absoluteString), ["https://b.example.com/rss"])
    }

    func testDetectsHTMLPayloads() {
        XCTAssertTrue(RSSFeedDiscovery.looksLikeHTML(Data("<!DOCTYPE html><html><head></head>".utf8)))
        XCTAssertFalse(RSSFeedDiscovery.looksLikeHTML(Data("<?xml version=\"1.0\"?><rss/>".utf8)))
    }

    func testFallbackURLsStayOnTheSameHost() throws {
        let urls = try RSSFeedDiscovery.fallbackFeedURLs(for: XCTUnwrap(URL(string: "https://c.example.com/blog/")))
        XCTAssertEqual(urls.count, 6)
        XCTAssertTrue(urls.allSatisfy { $0.host == "c.example.com" })
    }
}
