import Foundation

/// OPML 导入导出。
///
/// 这是迁移的必经之路：用户从别的阅读器搬过来时，只会带着一个 OPML 文件。导出的
/// 格式保持最朴素的 OPML 2.0，让别的阅读器也能读回去。
enum RSSOPML {
    struct ImportedFeed: Equatable, Sendable {
        var title: String?
        var feedURL: URL
        var siteURL: URL?
        var groupTitle: String?
    }

    struct ImportResult: Equatable, Sendable {
        var feeds: [ImportedFeed]
        /// 同一份文件里的重复订阅，导入时直接跳过。
        var duplicateCount: Int
    }

    static func importFeeds(from data: Data) throws -> ImportResult {
        let delegate = RSSOPMLImportDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.didFindOutline else {
            throw RSSFeedParserError.malformedXML("OPML 结构无法识别")
        }

        var seen: Set<String> = []
        var feeds: [ImportedFeed] = []
        var duplicates = 0
        for entry in delegate.entries {
            let key = entry.feedURL.absoluteString.lowercased()
            if seen.contains(key) {
                duplicates += 1
                continue
            }
            seen.insert(key)
            feeds.append(entry)
        }
        return ImportResult(feeds: feeds, duplicateCount: duplicates)
    }

    static func export(feeds: [RSSFeed], groups: [RSSGroup]) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<opml version=\"2.0\">",
            "  <head>",
            "    <title>Jarvis 订阅</title>",
            "    <dateCreated>\(RFC822Date.string(from: Date()))</dateCreated>",
            "  </head>",
            "  <body>"
        ]

        let grouped = Dictionary(grouping: feeds) { $0.groupID }
        for group in groups.sorted(by: { $0.order < $1.order }) {
            let members = grouped[group.id] ?? []
            guard !members.isEmpty else { continue }
            lines.append("    <outline text=\"\(escaped(group.title))\" title=\"\(escaped(group.title))\">")
            lines.append(contentsOf: members.map { outline(for: $0, indent: "      ") })
            lines.append("    </outline>")
        }
        for feed in feeds where feed.groupID == nil || !groups.contains(where: { $0.id == feed.groupID }) {
            lines.append(outline(for: feed, indent: "    "))
        }

        lines.append(contentsOf: ["  </body>", "</opml>", ""])
        return lines.joined(separator: "\n")
    }

    private static func outline(for feed: RSSFeed, indent: String) -> String {
        var attributes = [
            "text=\"\(escaped(feed.title))\"",
            "title=\"\(escaped(feed.title))\"",
            "type=\"rss\"",
            "xmlUrl=\"\(escaped(feed.feedURL.absoluteString))\""
        ]
        if let siteURL = feed.siteURL {
            attributes.append("htmlUrl=\"\(escaped(siteURL.absoluteString))\"")
        }
        return "\(indent)<outline \(attributes.joined(separator: " "))/>"
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private enum RFC822Date {
    private nonisolated(unsafe) static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

/// OPML 就是嵌套的 `<outline>`：带 `xmlUrl` 的是订阅，不带的是分组。
private final class RSSOPMLImportDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [RSSOPML.ImportedFeed] = []
    private(set) var didFindOutline = false
    /// 当前所在的分组标题：只认一层嵌套，够覆盖主流阅读器的导出格式。
    private var groupStack: [String] = []
    /// 与 `<outline>` 一一对应：只有分组容器才往 `groupStack` 里压过东西，
    /// 结束标签必须按同样的规则弹，否则订阅项会把分组弹掉。
    private var pushedGroupForOutline: [Bool] = []

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }
        didFindOutline = true
        let title = attributeDict["title"] ?? attributeDict["text"]

        guard let rawFeedURL = attributeDict["xmlUrl"] ?? attributeDict["xmlurl"] else {
            // 没有 xmlUrl 的是分组容器。
            groupStack.append(title ?? "")
            pushedGroupForOutline.append(true)
            return
        }
        pushedGroupForOutline.append(false)

        guard let url = URL(string: rawFeedURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return
        }

        let siteURL = (attributeDict["htmlUrl"] ?? attributeDict["htmlurl"])
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        entries.append(
            RSSOPML.ImportedFeed(
                title: title?.trimmingCharacters(in: .whitespacesAndNewlines),
                feedURL: url,
                siteURL: siteURL,
                groupTitle: groupStack.last(where: { !$0.isEmpty })
            )
        )
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        guard elementName.lowercased() == "outline" else { return }
        guard let pushedGroup = pushedGroupForOutline.popLast(), pushedGroup else { return }
        groupStack.removeLast()
    }
}
