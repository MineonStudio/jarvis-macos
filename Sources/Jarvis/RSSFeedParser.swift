import Foundation

struct RSSParsedEntry: Equatable, Sendable {
    var guid: String?
    var title: String
    var link: URL?
    var author: String?
    var publishedAt: Date?
    var summaryHTML: String
    var contentHTML: String?
    var enclosureURL: URL?
    var enclosureType: String?
}

struct RSSParsedFeed: Equatable, Sendable {
    var title: String?
    var siteURL: URL?
    var iconURL: URL?
    var entries: [RSSParsedEntry]
}

enum RSSFeedParserError: LocalizedError, Equatable {
    case malformedXML(String)
    case notAFeed

    var errorDescription: String? {
        switch self {
        case let .malformedXML(message): "订阅源解析失败：\(message)"
        case .notAFeed: "地址返回的内容不是 RSS/Atom 订阅源"
        }
    }
}

/// 把订阅源解成模型。
///
/// 真实世界里的 feed 很脏：编码不声明、CDATA 套 CDATA、日期格式各不相同、Atom 和
/// RSS 混着用。这里只保证一件事——能读出来的条目绝不因为某个字段读不出来而丢掉。
enum RSSFeedParser {
    /// 单次抓取最多接受的条目数，防止一个失控的 feed 把内存吃满。
    static let maximumEntryCount = 500
    /// 单条正文的字符上限。
    static let maximumContentCharacters = 512 * 1024

    static func parse(_ data: Data, baseURL: URL? = nil) throws -> RSSParsedFeed {
        let normalized = RSSFeedTextDecoder.utf8Data(from: data)
        let delegate = RSSFeedParserDelegate(baseURL: baseURL)
        let parser = XMLParser(data: normalized)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            let message = parser.parserError?.localizedDescription ?? "未知错误"
            throw RSSFeedParserError.malformedXML(message)
        }
        guard delegate.didRecognizeFeed else {
            throw RSSFeedParserError.notAFeed
        }
        return delegate.parsedFeed
    }

    /// 只判断像不像订阅源，用于「输入网址自动发现」时先探一下。
    static func looksLikeFeed(_ data: Data) -> Bool {
        let probe = data.prefix(512)
        guard let text = String(data: probe, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return false
        }
        return text.hasPrefix("<?xml")
            || text.hasPrefix("<rss")
            || text.hasPrefix("<feed")
            || text.hasPrefix("<rdf")
            || text.hasPrefix("{")
    }
}

/// 编码嗅探：BOM → XML 声明 → 常见中文编码回退。
///
/// `XMLParser` 只认 UTF-8 和声明了编码的文档，而不少中文博客的 feed 既不带 BOM 也
/// 不声明编码，直接喂进去就是一片解析错误。
enum RSSFeedTextDecoder {
    /// 中文编码在 Darwin 上不是 `String.Encoding` 的静态成员，要走 CFString 换算。
    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
    private static let big5 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    static func utf8Data(from data: Data) -> Data {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return data.dropFirst(3)
        }
        if let declared = declaredEncoding(in: data) {
            return transcode(data, using: declared) ?? data
        }
        if String(data: data, encoding: .utf8) != nil {
            return data
        }
        for encoding in [gb18030, big5, .windowsCP1252] {
            if let transcoded = transcode(data, using: encoding) {
                return transcoded
            }
        }
        return data
    }

    private static func declaredEncoding(in data: Data) -> String.Encoding? {
        let probe = data.prefix(200)
        guard let text = String(data: probe, encoding: .ascii) ?? String(data: probe, encoding: .isoLatin1) else {
            return nil
        }
        guard let range = text.range(of: "encoding", options: .caseInsensitive) else {
            return nil
        }
        let remainder = text[range.upperBound...]
        guard let open = remainder.firstIndex(of: "\""),
              let close = remainder[remainder.index(after: open)...].firstIndex(of: "\"")
        else {
            return nil
        }
        let value = remainder[remainder.index(after: open) ..< close].lowercased()
        switch value {
        case "utf-8", "utf8": return .utf8
        case "gb2312", "gbk", "gb18030": return gb18030
        case "big5": return big5
        case "iso-8859-1", "latin1": return .isoLatin1
        case "windows-1252", "cp1252": return .windowsCP1252
        default: return nil
        }
    }

    private static func transcode(_ data: Data, using encoding: String.Encoding) -> Data? {
        guard encoding != .utf8 else { return data }
        guard let text = String(data: data, encoding: encoding) else { return nil }
        // 转码后把声明里过时的编码名一起换掉，否则解析器会再按老编码解一遍。
        let rewritten = text.replacingOccurrences(
            of: "(?i)encoding=\"[^\"]+\"",
            with: "encoding=\"UTF-8\"",
            options: .regularExpression
        )
        return rewritten.data(using: .utf8)
    }
}

/// 日期解析的回退链。feed 里的日期格式没有统一过，认不出来时宁可不填，
/// 也不能让整条丢掉。
enum RSSDateParser {
    private static let lock = NSLock()
    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let fallbackFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm Z",
            "EEE MMM dd HH:mm:ss Z yyyy",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        return lock.withLock {
            if let date = iso8601.date(from: value) {
                return date
            }
            if let date = iso8601Fractional.date(from: value) {
                return date
            }
            for formatter in fallbackFormatters {
                if let date = formatter.date(from: value) {
                    return date
                }
            }
            return nil
        }
    }
}

/// 流式解析 XML。用「打开元素栈」保留每层的文本，这样即使 feed 把 HTML 直接塞进
/// 元素（而非 CDATA）导致解析器把标签当子元素，正文文本仍能拼回来。
private final class RSSFeedParserDelegate: NSObject, XMLParserDelegate {
    private let baseURL: URL?
    private var openElements: [(name: String, text: String)] = []
    private var entry: RSSParsedEntry?
    private var entryDepth = 0
    private(set) var didRecognizeFeed = false
    private(set) var parsedFeed = RSSParsedFeed(title: nil, siteURL: nil, iconURL: nil, entries: [])

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = Self.localName(elementName)
        openElements.append((name, ""))

        if openElements.count == 1 {
            switch name {
            case "rss", "feed", "rdf":
                didRecognizeFeed = true
            default:
                break
            }
        }

        switch name {
        case "item", "entry":
            entry = RSSParsedEntry(
                guid: attributeDict["rdf:about"] ?? attributeDict["about"],
                title: "",
                link: nil,
                author: nil,
                publishedAt: nil,
                summaryHTML: "",
                contentHTML: nil,
                enclosureURL: nil,
                enclosureType: nil
            )
            entryDepth = openElements.count
        case "link":
            handleLink(attributes: attributeDict)
        case "enclosure":
            handleEnclosure(attributes: attributeDict)
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard !openElements.isEmpty else { return }
        openElements[openElements.count - 1].text += string
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        guard !openElements.isEmpty,
              let text = String(data: CDATABlock, encoding: .utf8)
        else {
            return
        }
        openElements[openElements.count - 1].text += text
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        guard let frame = openElements.popLast() else { return }
        let text = frame.text
        let isClosingEntry = entryDepth == openElements.count + 1 && (frame.name == "item" || frame.name == "entry")
        // `localName` 会抹掉命名空间前缀，`<itunes:title>` 和 `<title>` 因此长得
        // 一模一样；带前缀的一律不当作条目自身的标题/链接。
        let isPrefixed = elementName.contains(":")

        if entry != nil {
            apply(entryField: frame.name, text: text, isPrefixed: isPrefixed)
        } else {
            applyFeedField(frame.name, text: text)
        }

        if isClosingEntry {
            if let entry {
                append(entry: entry)
            }
            entry = nil
            entryDepth = 0
        }

        // 子元素的文本并回父元素，正文里的标签就这样退化成文本而不是被丢掉。
        if !openElements.isEmpty {
            openElements[openElements.count - 1].text += text
        }
    }

    private func applyFeedField(_ name: String, text: String) {
        let value = Self.clean(text)
        switch name {
        case "title" where parsedFeed.title == nil:
            parsedFeed.title = value.isEmpty ? nil : value
        case "link" where parsedFeed.siteURL == nil:
            parsedFeed.siteURL = Self.absoluteURL(value, base: baseURL)
        case "icon", "logo":
            if let url = Self.absoluteURL(value, base: baseURL) {
                parsedFeed.iconURL = url
            }
        default:
            break
        }
    }

    private func apply(entryField name: String, text: String, isPrefixed: Bool) {
        guard entry != nil else { return }
        let value = Self.clean(text)
        // 标题和链接只认条目的直接子元素、且不带命名空间前缀：聚合站点的
        // `<source><title>` 在更深一层，播客的 `<itunes:title>` 则是靠前缀区分，
        // 两者都会把 `localName` 抹成 `title`，不设这两道就会覆盖真正的标题。
        let isOwnField = openElements.count == entryDepth && !isPrefixed
        switch name {
        case "title" where isOwnField:
            entry?.title = value
        case "link" where isOwnField:
            // Atom 的 link 走属性（handleLink），RSS 的走文本，这里补后者。
            if entry?.link == nil, let url = Self.absoluteURL(value, base: baseURL) {
                entry?.link = url
            }
        case "guid", "id":
            if entry?.guid == nil, !value.isEmpty {
                entry?.guid = value
            }
        case "description", "summary":
            if entry?.summaryHTML.isEmpty ?? false {
                entry?.summaryHTML = Self.truncated(value)
            }
        case "encoded", "content":
            if entry?.contentHTML == nil, !value.isEmpty {
                entry?.contentHTML = Self.truncated(value)
            }
        case "pubdate", "published", "updated", "date", "issued", "modified":
            if entry?.publishedAt == nil {
                entry?.publishedAt = RSSDateParser.parse(value)
            }
        case "creator", "author", "name":
            if entry?.author == nil, !value.isEmpty {
                entry?.author = value
            }
        default:
            break
        }
    }

    /// `<link>` 在 RSS 里是文本、在 Atom 里是属性，两种都要认。
    private func handleLink(attributes: [String: String]) {
        let rel = attributes["rel"]?.lowercased()
        if let href = attributes["href"] {
            let url = Self.absoluteURL(href, base: baseURL)
            if rel == "enclosure" {
                entry?.enclosureURL = url
                entry?.enclosureType = attributes["type"]
            } else if rel == nil || rel == "alternate" {
                if entry != nil {
                    if entry?.link == nil {
                        entry?.link = url
                    }
                } else if parsedFeed.siteURL == nil {
                    parsedFeed.siteURL = url
                }
            }
            return
        }
        // RSS：<link> 的文本要等 didEndElement 才拿得到，这里只处理属性。
    }

    private func handleEnclosure(attributes: [String: String]) {
        guard entry != nil, let raw = attributes["url"] else { return }
        entry?.enclosureURL = Self.absoluteURL(raw, base: baseURL)
        entry?.enclosureType = attributes["type"]
    }

    private func append(entry: RSSParsedEntry) {
        guard parsedFeed.entries.count < RSSFeedParser.maximumEntryCount else { return }
        var entry = entry
        if entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry.title = entry.link?.absoluteString ?? "无标题"
        }
        parsedFeed.entries.append(entry)
    }

    /// 去掉命名空间前缀：`content:encoded` → `encoded`，`dc:creator` → `creator`。
    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init)?.lowercased() ?? name.lowercased()
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncated(_ value: String) -> String {
        guard value.count > RSSFeedParser.maximumContentCharacters else { return value }
        return String(value.prefix(RSSFeedParser.maximumContentCharacters))
    }

    private static func absoluteURL(_ raw: String, base: URL?) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            let scheme = url.scheme?.lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
            return url
        }
        guard let base else { return nil }
        return URL(string: value, relativeTo: base)?.absoluteURL
    }
}
