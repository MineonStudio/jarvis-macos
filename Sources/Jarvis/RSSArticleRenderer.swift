import Foundation
import SwiftUI

/// 把文章 HTML 转成原生富文本。
///
/// 这里不引入 `WKWebView`：阅读视图的排版统一、可离线、可搜索，也不吃 GPU 能耗。
/// 代价是标签支持要走白名单——认不出的标签当文本处理，`script`/`style` 这类连同
/// 内容一起丢掉。渲染是「宽容」的：脏 HTML 只影响它自己那一小段，不能让整篇文章
/// 渲染失败。
enum RSSArticleRenderer {
    /// 正文里内联图片在首版只取第一张当题图，其余交给「在浏览器打开」。
    static func imageURLs(inHTML html: String, baseURL: URL?) -> [URL] {
        var urls: [URL] = []
        for token in RSSHTMLTokenizer.tokenize(html) {
            guard case let .startTag(name, attributes, _) = token, name == "img" else { continue }
            guard let raw = attributes["src"], let url = absoluteURL(raw, base: baseURL) else { continue }
            if !urls.contains(url) {
                urls.append(url)
            }
        }
        return urls
    }

    static func plainText(fromHTML html: String) -> String {
        var result = ""
        var skippedDepth = 0
        var blockBreakPending = false
        for token in RSSHTMLTokenizer.tokenize(html) {
            switch token {
            case let .text(text):
                guard skippedDepth == 0 else { continue }
                let decoded = RSSHTMLEntities.decode(text)
                let collapsed = collapsedWhitespace(decoded)
                guard !collapsed.isEmpty else { continue }
                if blockBreakPending, !result.isEmpty {
                    result.append("\n")
                }
                blockBreakPending = false
                result.append(collapsed)
            case let .startTag(name, _, selfClosing):
                if skippedElements.contains(name) {
                    skippedDepth += 1
                } else if blockElements.contains(name), !selfClosing || name == "br" {
                    blockBreakPending = true
                }
            case let .endTag(name):
                if skippedElements.contains(name) {
                    skippedDepth = max(0, skippedDepth - 1)
                } else if blockElements.contains(name) {
                    blockBreakPending = true
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func previewText(fromHTML html: String, limit: Int = 180) -> String {
        let text = plainText(fromHTML: html)
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func attributedString(
        fromHTML html: String,
        baseURL: URL? = nil,
        baseFont: Font = JarvisTypography.body,
        textColor: Color = .primary,
        secondaryColor: Color = .secondary,
        linkColor: Color = .accentColor
    ) -> AttributedString {
        let segments = RSSHTMLTextExtractor.segments(from: html, baseURL: baseURL)
        var output = AttributedString()

        for segment in segments {
            var container = AttributeContainer()
            container.font = segment.style.font(base: baseFont)
            container.foregroundColor = segment.linkURL == nil ? textColor : linkColor
            if let url = segment.linkURL {
                container.link = url
                container.underlineStyle = .single
            }
            if segment.style == .code {
                container.font = JarvisTypography.monospaced
            }
            var piece = AttributedString(segment.text)
            piece.setAttributes(container)
            output.append(piece)
        }

        _ = secondaryColor
        return output
    }

    static let skippedElements: Set<String> = [
        "script", "style", "iframe", "noscript", "svg", "form", "video", "audio", "object", "head"
    ]
    static let blockElements: Set<String> = [
        "p", "div", "br", "h1", "h2", "h3", "h4", "h5", "h6", "li", "ul", "ol",
        "blockquote", "pre", "table", "tr", "figure", "figcaption", "section", "article", "hr"
    ]

    static func collapsedWhitespace(_ value: String) -> String {
        var result = ""
        var lastWasSpace = false
        for character in value {
            if character.isWhitespace {
                if !lastWasSpace {
                    result.append(" ")
                }
                lastWasSpace = true
            } else {
                result.append(character)
                lastWasSpace = false
            }
        }
        return result
    }

    static func absoluteURL(_ raw: String, base: URL?) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), let scheme = url.scheme?.lowercased() {
            return (scheme == "http" || scheme == "https") ? url : nil
        }
        guard let base, let url = URL(string: value, relativeTo: base)?.absoluteURL else { return nil }
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") ? url : nil
    }
}

// MARK: - 分词

enum RSSHTMLToken {
    case text(String)
    case startTag(name: String, attributes: [String: String], selfClosing: Bool)
    case endTag(String)
}

/// 容错的 HTML 分词器：只关心标签边界和属性，不建树，所以未闭合的标签不会让它
/// 卡住或者丢内容。
enum RSSHTMLTokenizer {
    static func tokenize(_ html: String) -> [RSSHTMLToken] {
        var tokens: [RSSHTMLToken] = []
        var index = html.startIndex
        let end = html.endIndex

        while index < end {
            guard let tagStart = html[index...].firstIndex(of: "<") else {
                tokens.append(.text(String(html[index...])))
                break
            }
            if tagStart > index {
                tokens.append(.text(String(html[index ..< tagStart])))
            }
            guard let tagEnd = findTagEnd(in: html, from: tagStart) else {
                tokens.append(.text(String(html[tagStart...])))
                break
            }
            let raw = String(html[tagStart ... tagEnd])
            if let token = parseTag(raw) {
                tokens.append(token)
            }
            index = html.index(after: tagEnd)
        }
        return tokens
    }

    /// 找 `>` 时要跳过引号里的内容：`<a title="a>b">` 里的 `>` 不是标签结尾。
    private static func findTagEnd(in html: String, from start: String.Index) -> String.Index? {
        var cursor = html.index(after: start)
        var quote: Character?
        while cursor < html.endIndex {
            let character = html[cursor]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = html.index(after: cursor)
        }
        return nil
    }

    private static func parseTag(_ raw: String) -> RSSHTMLToken? {
        if raw.hasPrefix("<!--") || raw.hasPrefix("<!") || raw.hasPrefix("<?") {
            return nil
        }
        var body = raw.dropFirst()
        let isClosing = body.hasPrefix("/")
        if isClosing {
            body = body.dropFirst()
        }
        let selfClosing = body.hasSuffix("/")
        if selfClosing {
            body = body.dropLast()
        }
        if body.hasSuffix(">") {
            body = body.dropLast()
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let nameEnd = trimmed.firstIndex { $0.isWhitespace } ?? trimmed.endIndex
        let name = String(trimmed[trimmed.startIndex ..< nameEnd]).lowercased()
        guard !name.isEmpty else { return nil }
        if isClosing {
            return .endTag(name)
        }
        let attributeText = String(trimmed[nameEnd...])
        return .startTag(
            name: name,
            attributes: attributeMap(in: attributeText),
            selfClosing: selfClosing
        )
    }

    private static func attributeMap(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        var cursor = text.startIndex
        while cursor < text.endIndex {
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            let nameStart = cursor
            while cursor < text.endIndex, !text[cursor].isWhitespace, text[cursor] != "=" {
                cursor = text.index(after: cursor)
            }
            let name = String(text[nameStart ..< cursor]).lowercased()
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex, text[cursor] == "=" else {
                if !name.isEmpty {
                    result[name] = ""
                }
                continue
            }
            cursor = text.index(after: cursor)
            while cursor < text.endIndex, text[cursor].isWhitespace {
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex else { break }
            let quote = text[cursor]
            if quote == "\"" || quote == "'" {
                let valueStart = text.index(after: cursor)
                var valueEnd = valueStart
                while valueEnd < text.endIndex, text[valueEnd] != quote {
                    valueEnd = text.index(after: valueEnd)
                }
                result[name] = String(text[valueStart ..< valueEnd])
                cursor = valueEnd < text.endIndex ? text.index(after: valueEnd) : text.endIndex
            } else {
                let valueStart = cursor
                while cursor < text.endIndex, !text[cursor].isWhitespace {
                    cursor = text.index(after: cursor)
                }
                result[name] = String(text[valueStart ..< cursor])
            }
            if !name.isEmpty, result[name] == "" {
                result[name] = name
            }
        }
        return result
    }
}

// MARK: - 富文本片段

private struct RSSHTMLSegment {
    enum Style: Equatable {
        case body
        case heading(Int)
        case code
        case quote
        case listItem(marker: String)

        func font(base: Font) -> Font {
            switch self {
            case .body:
                base
            case let .heading(level):
                switch level {
                case 1: .system(size: 22, weight: .semibold)
                case 2: .system(size: 19, weight: .semibold)
                case 3: .system(size: 16, weight: .semibold)
                default: .system(size: 15, weight: .semibold)
                }
            case .code:
                JarvisTypography.monospaced
            case .quote:
                .system(size: 14).italic()
            case .listItem:
                base
            }
        }
    }

    var text: String
    var style: Style
    var linkURL: URL?
}

/// 把分词结果按白名单折叠成带样式的文本片段。
private enum RSSHTMLTextExtractor {
    static func segments(from html: String, baseURL: URL?) -> [RSSHTMLSegment] {
        var state = RSSHTMLTextState()
        for token in RSSHTMLTokenizer.tokenize(html) {
            switch token {
            case let .text(raw):
                state.handleText(raw)
            case let .startTag(name, attributes, _):
                state.handleStartTag(name, attributes: attributes, baseURL: baseURL)
            case let .endTag(name):
                state.handleEndTag(name)
            }
        }
        state.trimSurroundingBreaks()
        return state.segments
    }
}

/// 折叠过程中的全部状态。拆成结构体是为了让每种标签各有一个小处理函数——
/// 塞进一个 switch 里会变成一坨谁也读不动、复杂度也过不了 lint 的代码。
private struct RSSHTMLTextState {
    var segments: [RSSHTMLSegment] = []
    /// 栈里带上标签名，结束标签才知道该弹哪一层（`code` 套在 `pre` 里时必须分得清）。
    var styleStack: [(tag: String, style: RSSHTMLSegment.Style)] = []
    var linkStack: [URL] = []
    var skippedDepth = 0
    var pendingBreak = 0
    var listStack: [(ordered: Bool, index: Int)] = []
    var inPre = false

    private var currentStyle: RSSHTMLSegment.Style {
        if let style = styleStack.last?.style {
            return style
        }
        return listStack.isEmpty ? .body : .listItem(marker: "")
    }

    private mutating func popStyle(tag: String) {
        if styleStack.last?.tag == tag {
            styleStack.removeLast()
        }
    }

    private mutating func append(_ text: String, style: RSSHTMLSegment.Style) {
        guard !text.isEmpty else { return }
        segments.append(RSSHTMLSegment(text: text, style: style, linkURL: linkStack.last))
    }

    private mutating func flushBreaks() {
        guard pendingBreak > 0 else { return }
        append(String(repeating: "\n", count: pendingBreak), style: .body)
        pendingBreak = 0
    }

    private mutating func requestBreak(_ count: Int) {
        pendingBreak = max(pendingBreak, count)
    }

    mutating func handleText(_ raw: String) {
        guard skippedDepth == 0 else { return }
        let decoded = RSSHTMLEntities.decode(raw)
        let text = inPre ? decoded : RSSArticleRenderer.collapsedWhitespace(decoded)
        guard !text.isEmpty, text != " " || segments.isEmpty else { return }
        flushBreaks()
        append(text, style: currentStyle)
    }

    mutating func handleStartTag(_ name: String, attributes: [String: String], baseURL: URL?) {
        if RSSArticleRenderer.skippedElements.contains(name) {
            skippedDepth += 1
            return
        }
        guard skippedDepth == 0 else { return }

        applySpacingStartTag(name)
        applySectionStartTag(name)
        applyListStartTag(name)
        applyLinkStartTag(name, attributes: attributes, baseURL: baseURL)
    }

    mutating func handleEndTag(_ name: String) {
        if RSSArticleRenderer.skippedElements.contains(name) {
            skippedDepth = max(0, skippedDepth - 1)
            return
        }
        guard skippedDepth == 0 else { return }

        applySpacingEndTag(name)
        applySectionEndTag(name)
        applyListEndTag(name)
        applyLinkEndTag(name)
    }

    mutating func trimSurroundingBreaks() {
        while let first = segments.first, first.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.removeFirst()
        }
        while let last = segments.last, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.removeLast()
        }
    }

    /// 段落类标签只影响换行。
    private mutating func applySpacingStartTag(_ name: String) {
        switch name {
        case "br":
            requestBreak(1)
        case "hr":
            flushBreaks()
            append("\n———\n", style: .body)
            requestBreak(2)
        case "p", "div", "section", "article", "figure", "figcaption", "table", "tr":
            requestBreak(2)
        default:
            break
        }
    }

    private mutating func applySpacingEndTag(_ name: String) {
        switch name {
        case "p", "div", "section", "article", "figure", "figcaption", "table", "tr":
            requestBreak(2)
        default:
            break
        }
    }

    /// 影响行内样式的容器标签：标题、引用、代码。
    private mutating func applySectionStartTag(_ name: String) {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            requestBreak(2)
            flushBreaks()
            if let level = Int(name.dropFirst()) {
                styleStack.append((name, .heading(level)))
            }
        case "blockquote":
            requestBreak(2)
            styleStack.append((name, .quote))
        case "pre":
            requestBreak(2)
            inPre = true
            styleStack.append((name, .code))
        case "code":
            styleStack.append((name, .code))
        default:
            break
        }
    }

    private mutating func applySectionEndTag(_ name: String) {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre":
            popStyle(tag: name)
            requestBreak(2)
        case "code":
            if !inPre {
                popStyle(tag: name)
            }
        default:
            break
        }
        if name == "pre" {
            inPre = false
        }
    }

    private mutating func applyListStartTag(_ name: String) {
        switch name {
        case "ul", "ol":
            requestBreak(1)
            listStack.append((ordered: name == "ol", index: 1))
        case "li":
            requestBreak(1)
            flushBreaks()
            guard var current = listStack.popLast() else { return }
            let marker = current.ordered ? "\(current.index). " : "• "
            current.index += 1
            listStack.append(current)
            append(marker, style: .body)
        default:
            break
        }
    }

    private mutating func applyListEndTag(_ name: String) {
        guard name == "ul" || name == "ol" else { return }
        _ = listStack.popLast()
        requestBreak(2)
    }

    private mutating func applyLinkStartTag(
        _ name: String,
        attributes: [String: String],
        baseURL: URL?
    ) {
        switch name {
        case "a":
            guard let href = attributes["href"],
                  let url = RSSArticleRenderer.absoluteURL(href, base: baseURL)
            else {
                return
            }
            linkStack.append(url)
        case "img":
            // 首版不在正文里插图片，题图由详情页单独渲染。
            break
        default:
            break
        }
    }

    private mutating func applyLinkEndTag(_ name: String) {
        guard name == "a", !linkStack.isEmpty else { return }
        linkStack.removeLast()
    }
}

/// HTML 实体解码。覆盖正文里真正会出现的那些，其余保持原样而不是变成空白。
enum RSSHTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "middot": "·", "bull": "•",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "laquo": "«", "raquo": "»", "times": "×", "copy": "©", "reg": "®", "trade": "™",
        "deg": "°", "plusmn": "±", "frac12": "½", "euro": "€", "pound": "£", "yen": "¥",
        "ensp": " ", "emsp": " ", "thinsp": " "
    ]

    static func decode(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = ""
        var index = value.startIndex

        while index < value.endIndex {
            guard value[index] == "&",
                  let semicolon = value[index...].firstIndex(of: ";"),
                  value.distance(from: index, to: semicolon) <= 12
            else {
                result.append(value[index])
                index = value.index(after: index)
                continue
            }

            let entity = String(value[value.index(after: index) ..< semicolon])
            if let decoded = decodeEntity(entity) {
                result.append(decoded)
                index = value.index(after: semicolon)
            } else {
                result.append(value[index])
                index = value.index(after: index)
            }
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let body = entity.dropFirst()
            let scalarValue: UInt32? = if body.hasPrefix("x") || body.hasPrefix("X") {
                UInt32(body.dropFirst(), radix: 16)
            } else {
                UInt32(body)
            }
            guard let value = scalarValue, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }
        return named[entity.lowercased()]
    }
}
