import Foundation

enum EntertainmentVideoLink {
    static func match(_ raw: String) -> (url: URL, platform: EntertainmentPlatform)? {
        let candidates = urlCandidates(in: raw)
        for candidate in candidates {
            if let platform = platform(for: candidate) {
                return (candidate, platform)
            }
        }
        return nil
    }

    static func platform(for url: URL) -> EntertainmentPlatform? {
        guard let host = url.host?.lowercased() else { return nil }
        if isYouTubeHost(host), isYouTubePath(url) {
            return .youtube
        }
        if isXHost(host), isXPath(url) {
            return .x
        }
        if isTikTokHost(host), isTikTokPath(url) {
            return .tiktok
        }
        return nil
    }

    static func urlCandidates(in raw: String) -> [URL] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen: Set<String> = []
        var urls: [URL] = []
        let tokens = trimmed.components(separatedBy: .whitespacesAndNewlines)
        let combined = [trimmed] + tokens
        for token in combined {
            let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
            guard let url = URL(string: cleaned),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil
            else {
                continue
            }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            urls.append(url)
        }
        return urls
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
    }

    private static func isXHost(_ host: String) -> Bool {
        host == "x.com" || host.hasSuffix(".x.com")
            || host == "twitter.com" || host.hasSuffix(".twitter.com")
    }

    private static func isTikTokHost(_ host: String) -> Bool {
        host == "tiktok.com" || host.hasSuffix(".tiktok.com")
            || host == "tiktokv.com" || host.hasSuffix(".tiktokv.com")
    }

    private static func isYouTubePath(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host == "youtu.be" {
            return !url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
        }
        let path = url.path.lowercased()
        if path.contains("/watch") {
            return true
        }
        return path.contains("/shorts/")
            || path.contains("/embed/")
            || path.contains("/live/")
            || path.contains("/clip/")
    }

    private static func isXPath(_ url: URL) -> Bool {
        url.path.lowercased().contains("/status/")
    }

    private static func isTikTokPath(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if host.hasPrefix("vm.") || host.hasPrefix("vt.") {
            return true
        }
        let path = url.path.lowercased()
        return path.contains("/video/")
            || path.contains("/t/")
            || path.contains("/photo/")
    }
}
