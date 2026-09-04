import Foundation

enum HermesEnvFile {
    static func parse(_ content: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let stripped = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                : line
            guard let separator = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[..<separator]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(stripped[stripped.index(after: separator)...])
            guard !key.isEmpty else { continue }
            values[key] = unquote(rawValue)
        }
        return values
    }

    static func upsert(_ updates: [String: String], into content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        if lines.last == "" {
            lines.removeLast()
        }
        var remaining = updates
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { continue }
            let stripped = trimmed.hasPrefix("export ")
                ? String(trimmed.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
                : trimmed
            guard let separator = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[..<separator]).trimmingCharacters(in: .whitespaces)
            guard let value = remaining.removeValue(forKey: key) else { continue }
            lines[index] = "\(key)=\(quotedValue(value))"
        }
        for key in remaining.keys.sorted() {
            guard let value = remaining[key] else { continue }
            lines.append("\(key)=\(quotedValue(value))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func quotedValue(_ value: String) -> String {
        let specials = CharacterSet(charactersIn: "#\"$\\'")
        let needsQuotes = value.contains(where: { character in
            character.isWhitespace
                || character.unicodeScalars.contains { specials.contains($0) }
        })
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquote(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2 {
            if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                let inner = String(trimmed.dropFirst().dropLast())
                return inner
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            if trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
                return String(trimmed.dropFirst().dropLast())
            }
        }
        if let comment = trimmed.firstIndex(of: "#"),
           !trimmed[..<comment].contains("\"")
        {
            return String(trimmed[..<comment]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}

enum HermesYAML {
    struct ModelMapping: Equatable, Sendable {
        var provider: String
        var model: String
        var baseURL: String
        var apiMode: String

        static let openaiCompatible = "openai"
        static let chatCompletions = "chat_completions"
    }

    static func parseModelMapping(from yaml: String) -> [String: String] {
        let lines = yaml.components(separatedBy: .newlines)
        var inModel = false
        var mapping: [String: String] = [:]
        for line in lines {
            if !inModel {
                guard let value = topLevelValue(in: line, key: "model") else { continue }
                if value.isEmpty {
                    inModel = true
                    continue
                }
                let scalar = unquote(value)
                return scalar.isEmpty ? [:] : ["default": scalar]
            }

            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }
            if !isIndented(line) {
                break
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                continue
            }
            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            mapping[key] = unquote(value)
        }
        return mapping
    }

    static func upsertModel(
        in yaml: String,
        mapping: ModelMapping
    ) -> String {
        let block = modelBlock(mapping)
        let lines = yaml.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { topLevelKey($0) == "model" }) else {
            let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return block
            }
            return block + "\n" + yaml.trimmingCharacters(in: CharacterSet.newlines) + "\n"
        }

        var end = start + 1
        if let value = topLevelValue(in: lines[start], key: "model"), value.isEmpty {
            while end < lines.count {
                let line = lines[end]
                if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isIndented(line) {
                    end += 1
                    continue
                }
                break
            }
        } else {
            end = start + 1
        }

        let prefix = lines[..<start].joined(separator: "\n")
        let suffix = end < lines.count ? lines[end...].joined(separator: "\n") : ""
        var parts: [String] = []
        if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(prefix.trimmingCharacters(in: CharacterSet.newlines))
        }
        parts.append(block.trimmingCharacters(in: CharacterSet.newlines))
        if !suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(suffix.trimmingCharacters(in: CharacterSet.newlines))
        }
        return parts.joined(separator: "\n") + "\n"
    }

    static func modelBlock(_ mapping: ModelMapping) -> String {
        """
        model:
          provider: \(scalar(mapping.provider))
          default: \(scalar(mapping.model))
          base_url: \(scalar(mapping.baseURL))
          api_mode: \(scalar(mapping.apiMode))
        """ + "\n"
    }

    private static func topLevelKey(_ line: String) -> String? {
        guard !isIndented(line) else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: ":") else {
            return nil
        }
        return String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
    }

    private static func topLevelValue(in line: String, key: String) -> String? {
        guard topLevelKey(line) == key else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let separator = trimmed.firstIndex(of: ":") else { return nil }
        return String(trimmed[trimmed.index(after: separator)...])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t")
    }

    private static func unquote(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        if trimmed == "\"\"" || trimmed == "''" {
            return ""
        }
        if trimmed.count >= 2 {
            if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
                return String(trimmed.dropFirst().dropLast())
            }
            if trimmed.hasPrefix("'"), trimmed.hasSuffix("'") {
                return String(trimmed.dropFirst().dropLast())
            }
        }
        return trimmed
    }

    private static func scalar(_ value: String) -> String {
        if value.isEmpty {
            return "''"
        }
        let needsQuotes = value.contains(where: { ":#{}[]&*?|>!%@`,".contains($0) || $0.isWhitespace })
            || value.hasPrefix("-")
            || value.hasPrefix("*")
        guard needsQuotes else { return value }
        let escaped = value.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }
}
