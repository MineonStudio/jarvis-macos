import Foundation

struct RSSFetchRequest: Sendable, Equatable {
    var url: URL
    var etag: String?
    var lastModified: String?

    init(url: URL, etag: String? = nil, lastModified: String? = nil) {
        self.url = url
        self.etag = etag
        self.lastModified = lastModified
    }

    /// 条件请求头在这里拼：命中 304 时整轮抓取只剩一次往返。
    func urlRequest(userAgent: String, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "application/rss+xml, application/atom+xml, application/xml;q=0.9, "
                + "text/xml;q=0.8, text/html;q=0.7, */*;q=0.1",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return request
    }
}

struct RSSFetchResponse: Sendable {
    var data: Data
    var etag: String?
    var lastModified: String?
    /// 服务端确认内容没变，调用方直接跳过解析与落盘。
    var notModified: Bool

    static let unchanged = RSSFetchResponse(data: Data(), etag: nil, lastModified: nil, notModified: true)
}

protocol RSSFeedFetching: Sendable {
    func fetch(_ request: RSSFetchRequest) async throws -> RSSFetchResponse
}

enum RSSFeedClientError: LocalizedError, Equatable {
    case invalidResponse
    case httpStatus(Int)
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "服务器返回了无法识别的响应"
        case let .httpStatus(code): "服务器返回 \(code)"
        case .responseTooLarge: "订阅源体积超出上限"
        }
    }
}

struct RSSFeedClient: RSSFeedFetching {
    /// 订阅源不该这么大；超过这个量级的多半是被重定向到了别的东西。
    static let maximumResponseBytes = 10 * 1024 * 1024

    private let session: URLSession
    private let userAgent: String

    init(session: URLSession = RSSFeedClient.makeDefaultSession(), userAgent: String? = nil) {
        self.session = session
        self.userAgent = userAgent ?? RSSFeedClient.defaultUserAgent
    }

    /// 伪装成主流阅读器的 UA：不少站点对陌生 UA 直接返回 403 或不给完整 feed。
    static var defaultUserAgent: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Jarvis/\(JarvisAppVersion.shortVersion) (macOS \(version.majorVersion).\(version.minorVersion)) "
            + "AppleWebKit/605.1.15"
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        // 条件请求由我们自己发，别再叠一层本地缓存。
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"]
        return URLSession(configuration: configuration)
    }

    func fetch(_ request: RSSFetchRequest) async throws -> RSSFetchResponse {
        let (data, response) = try await session.data(for: request.urlRequest(userAgent: userAgent))
        guard let http = response as? HTTPURLResponse else {
            throw RSSFeedClientError.invalidResponse
        }
        if http.statusCode == 304 {
            return RSSFetchResponse(
                data: Data(),
                etag: http.value(forHTTPHeaderField: "ETag") ?? request.etag,
                lastModified: http.value(forHTTPHeaderField: "Last-Modified") ?? request.lastModified,
                notModified: true
            )
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw RSSFeedClientError.httpStatus(http.statusCode)
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw RSSFeedClientError.responseTooLarge
        }
        return RSSFetchResponse(
            data: data,
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
            notModified: false
        )
    }
}

/// 从网页里找订阅源地址。用户只会记得网站首页，不会记得 feed 的路径。
enum RSSFeedDiscovery {
    static let feedMIMETypes: Set<String> = [
        "application/rss+xml",
        "application/atom+xml",
        "application/feed+json",
        "application/json",
        "text/xml",
        "application/xml"
    ]

    /// 解析 `<link rel="alternate" type="application/rss+xml" href="...">`。
    /// 用正则而不是 HTML 解析器：只需要抓标签属性，容错比严谨更值钱。
    static func feedURLs(inHTML html: String, baseURL: URL) -> [URL] {
        let pattern = "<link\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var results: [URL] = []
        for match in regex.matches(in: html, options: [], range: range) {
            guard let matchRange = Range(match.range, in: html) else { continue }
            let tag = String(html[matchRange])
            let attributes = attributeMap(in: tag)
            guard let href = attributes["href"] else { continue }
            let rel = attributes["rel"]?.lowercased()
            guard rel == nil || rel == "alternate" else { continue }
            guard let type = attributes["type"]?.lowercased(),
                  feedMIMETypes.contains(type.split(separator: ";").first.map(String.init) ?? type)
            else {
                continue
            }
            guard let url = absoluteURL(href, base: baseURL), !results.contains(url) else { continue }
            results.append(url)
        }
        return results
    }

    static func looksLikeHTML(_ data: Data) -> Bool {
        let probe = data.prefix(512)
        guard let text = String(data: probe, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }
        return text.hasPrefix("<!doctype html") || text.hasPrefix("<html") || text.contains("<head")
    }

    /// 站点常见的兜底路径，`<link>` 标签缺失时再试这几个。
    static func fallbackFeedURLs(for siteURL: URL) -> [URL] {
        ["feed", "rss", "atom.xml", "feed.xml", "rss.xml", "index.xml"].compactMap { path in
            URL(string: path, relativeTo: siteURL.appendingPathComponent(""))?.absoluteURL
        }
    }

    private static func attributeMap(in tag: String) -> [String: String] {
        let pattern = "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var result: [String: String] = [:]
        let range = NSRange(tag.startIndex..., in: tag)
        for match in regex.matches(in: tag, options: [], range: range) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()
            for group in [3, 4] where match.range(at: group).location != NSNotFound {
                if let valueRange = Range(match.range(at: group), in: tag) {
                    result[name] = String(tag[valueRange])
                    break
                }
            }
        }
        return result
    }

    private static func absoluteURL(_ raw: String, base: URL) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased() {
            return (scheme == "http" || scheme == "https") ? url : nil
        }
        guard let url = URL(string: value, relativeTo: base)?.absoluteURL else { return nil }
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") ? url : nil
    }
}
