import AppKit
import Foundation

enum HermesPasteObject: Equatable, Sendable {
    case file(URL)
    case image
    case url(String)
}

struct HermesPasteClassification: Equatable, Sendable {
    var objects: [HermesPasteObject]
    var insertText: String?

    var hasObjects: Bool {
        !objects.isEmpty
    }
}

enum HermesPasteClassifier {
    static func classify(
        fileURLs: [URL],
        hasImage: Bool,
        text: String?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> HermesPasteClassification {
        if !fileURLs.isEmpty {
            return HermesPasteClassification(
                objects: fileURLs.map { .file($0.standardizedFileURL) },
                insertText: nil
            )
        }

        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if hasImage {
            var objects: [HermesPasteObject] = [.image]
            if let url = httpURL(from: trimmed) {
                objects.append(.url(url))
                return HermesPasteClassification(objects: objects, insertText: nil)
            }
            if let path = existingFileURL(from: trimmed, fileExists: fileExists) {
                objects.append(.file(path))
                return HermesPasteClassification(objects: objects, insertText: nil)
            }
            return HermesPasteClassification(
                objects: objects,
                insertText: trimmed.isEmpty ? nil : trimmed
            )
        }

        if trimmed.isEmpty {
            return HermesPasteClassification(objects: [], insertText: nil)
        }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lineObjects = lines.compactMap { line -> HermesPasteObject? in
            if let url = httpURL(from: line) {
                return .url(url)
            }
            if let path = existingFileURL(from: line, fileExists: fileExists) {
                return .file(path)
            }
            return nil
        }
        if !lineObjects.isEmpty, lineObjects.count == lines.count {
            return HermesPasteClassification(objects: lineObjects, insertText: nil)
        }
        return HermesPasteClassification(objects: [], insertText: nil)
    }

    static func httpURL(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return nil
        }
        return trimmed
    }

    static func existingFileURL(
        from rawValue: String,
        fileExists: (String) -> Bool
    ) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.isFileURL {
            return fileExists(url.path) ? url.standardizedFileURL : nil
        }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard fileExists(expanded) else { return nil }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
}

struct HermesComposerHistoryState: Equatable, Sendable {
    var cursor = -1
    var draftSnapshot = ""

    var isBrowsing: Bool {
        cursor >= 0
    }

    mutating func browseBackward(currentDraft: String, history: [String]) -> String? {
        guard !history.isEmpty else { return nil }
        if cursor == -1 {
            draftSnapshot = currentDraft
            cursor = 0
        } else if cursor < history.count - 1 {
            cursor += 1
        } else {
            return nil
        }
        return history[cursor]
    }

    mutating func browseForward(history: [String]) -> String? {
        guard cursor >= 0 else { return nil }
        if cursor > 0 {
            cursor -= 1
            return history[cursor]
        }
        let text = draftSnapshot
        cursor = -1
        draftSnapshot = ""
        return text
    }

    mutating func reset() {
        cursor = -1
        draftSnapshot = ""
    }
}

enum HermesComposerHistory {
    static func userEntries(from messages: [HermesChatMessage]) -> [String] {
        messages.reversed().compactMap { message in
            guard message.role == .user else { return nil }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
