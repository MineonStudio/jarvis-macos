import Foundation

enum HermesAgentLogParser {
    static func status(from line: String) -> String? {
        let trimmed = stripLogPrefix(line)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("FreeUsageLimitError")
            || trimmed.contains("Rate limit exceeded")
            || trimmed.contains("HTTP 429")
            || trimmed.localizedCaseInsensitiveContains("rate limit")
        {
            return "免费额度已用完，正在重试…"
        }
        if trimmed.contains("Retrying API call") {
            return "接口繁忙，正在重试…"
        }
        if let model = matchTwo(trimmed, pattern: #"conversation turn:.*model=(\S+)\s+provider=(\S+)"#) {
            let title = HermesProviderCatalog.groupTitle(forSlug: model.1)
            return "正在用 \(title)（\(model.0)）思考"
        }
        if trimmed.contains("starting API call") || trimmed.contains("Making API call") {
            return "正在请求模型…"
        }
        if let call = matchThree(trimmed, pattern: #"API call #(\d+): model=(\S+) provider=(\S+)"#) {
            return "第 \(call.0) 次请求 \(call.1)"
        }
        if trimmed.contains("waiting for provider response")
            || trimmed.contains("receiving stream response")
        {
            return "正在接收回复…"
        }
        if trimmed.contains("local model loading") {
            return "正在加载本地模型…"
        }
        if let tool = firstCapture(trimmed, pattern: #"tool ([A-Za-z0-9_./-]+) failed"#) {
            return "\(friendlyToolName(tool))失败"
        }
        if let tool = firstCapture(trimmed, pattern: #"tool ([A-Za-z0-9_./-]+) completed"#) {
            return "已完成：\(friendlyToolName(tool))"
        }
        if let tool = firstCapture(trimmed, pattern: #"tool ([A-Za-z0-9_./-]+) cancelled"#) {
            return "已取消：\(friendlyToolName(tool))"
        }
        if trimmed.contains("Turn ended") {
            return "正在整理回复…"
        }
        return nil
    }

    static func failureReason(stderr: String, log: String) -> String? {
        let combined = stderr + "\n" + log
        if combined.contains("FreeUsageLimitError")
            || combined.contains("Rate limit exceeded")
        {
            return "免费模型额度已用完，请稍后再试或换成 DeepSeek / xAI"
        }
        if let errorLine = combined.split(separator: "\n").reversed().compactMap({ line -> String? in
            let text = stripLogPrefix(String(line))
            if text.hasPrefix("Error:") {
                return String(text.dropFirst("Error:".count)).trimmingCharacters(in: .whitespaces)
            }
            return nil
        }).first, !errorLine.isEmpty {
            return errorLine
        }
        return cleanedStderr(stderr)
    }

    static func cleanedStderr(_ raw: String) -> String? {
        let ignored = ["Resumed session", "Model restored from session", "session_id:"]
        let useful = raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { stripLogPrefix(String($0)) }
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                return !ignored.contains { trimmed.hasPrefix($0) || trimmed.contains($0) }
            }
        let joined = useful.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    static func friendlyToolName(_ raw: String) -> String {
        let name = raw.split(separator: "/").last.map(String.init) ?? raw
        switch name {
        case "read_file", "read": return "读取文件"
        case "write_file", "write": return "写入文件"
        case "edit_file", "patch", "str_replace": return "修改文件"
        case "list_dir", "glob", "search_files": return "查找文件"
        case "web_search": return "搜索网络"
        case "web_extract", "web_fetch": return "读取网页"
        case "terminal", "execute", "run_command", "execute_code": return "执行命令"
        case "browser", "browser_navigate": return "浏览网页"
        case "todo", "todo_list": return "更新待办"
        case "memory": return "读写记忆"
        default: return name
        }
    }

    private static func stripLogPrefix(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let ansi = try? NSRegularExpression(pattern: #"\u001B\[[0-9;]*[A-Za-z]"#) {
            text = ansi.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        if let range = text.range(of: #"^\d{4}-\d{2}-\d{2} [0-9:,.]+ "#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        for marker in ["INFO ", "WARNING ", "ERROR ", "DEBUG "] {
            if let range = text.range(of: marker), text.distance(from: text.startIndex, to: range.lowerBound) < 80 {
                text = String(text[range.upperBound...])
                if let bracket = text.firstIndex(of: "]") {
                    let after = text.index(after: bracket)
                    if after < text.endIndex, text[after] == " " {
                        text = String(text[text.index(after: after)...])
                    }
                }
                break
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func firstCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private static func matchTwo(_ text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 2,
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text)
        else { return nil }
        return (String(text[first]), String(text[second]))
    }

    private static func matchThree(_ text: String, pattern: String) -> (String, String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 3,
              let first = Range(match.range(at: 1), in: text),
              let second = Range(match.range(at: 2), in: text),
              let third = Range(match.range(at: 3), in: text)
        else { return nil }
        return (String(text[first]), String(text[second]), String(text[third]))
    }
}
