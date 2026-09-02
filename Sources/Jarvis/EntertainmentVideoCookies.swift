import Foundation
import WebKit

enum NetscapeCookieFile {
    static func serialize(_ cookies: [HTTPCookie]) -> String {
        var lines = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            lines.append(line(for: cookie))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func line(for cookie: HTTPCookie) -> String {
        let domain = cookie.domain
        let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
        let path = cookie.path.isEmpty ? "/" : cookie.path
        let secure = cookie.isSecure ? "TRUE" : "FALSE"
        let expiry = cookie.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
        let prefix = cookie.isHTTPOnly ? "#HttpOnly_" : ""
        return "\(prefix)\(domain)\t\(includeSubdomains)\t\(path)\t\(secure)\t\(expiry)\t\(cookie.name)\t\(cookie.value)"
    }

    static func isRelevant(_ cookie: HTTPCookie, to url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == domain || host.hasSuffix(".\(domain)") || domain.hasSuffix(".\(host)") {
            return true
        }
        let isYouTube = host.contains("youtube") || host == "youtu.be" || host.hasSuffix(".youtu.be")
        guard isYouTube else { return false }
        return domain.hasSuffix("youtube.com")
            || domain.hasSuffix("youtu.be")
            || domain.hasSuffix("google.com")
            || domain.hasSuffix("googleusercontent.com")
    }
}

enum WKWebsiteCookieExport {
    static func writeNetscapeFile(matching url: URL) async -> URL? {
        let cookies = await allCookies()
        let filtered = cookies.filter { NetscapeCookieFile.isRelevant($0, to: url) }
        guard !filtered.isEmpty else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-cookies-\(UUID().uuidString).txt")
        do {
            try NetscapeCookieFile.serialize(filtered).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return file
        } catch {
            return nil
        }
    }

    private static func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

enum BinaryLocator {
    static func find(
        names: [String],
        extraPaths: [String]
    ) -> URL? {
        var candidates = extraPaths
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            for name in names {
                candidates.append("\(directory)/\(name)")
            }
        }
        var seen: Set<String> = []
        for path in candidates {
            guard seen.insert(path).inserted,
                  FileManager.default.isExecutableFile(atPath: path)
            else { continue }
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func ffmpeg() -> URL? {
        find(names: ["ffmpeg"], extraPaths: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ])
    }

    static func jsRuntimeArgument() -> String? {
        if let deno = find(names: ["deno"], extraPaths: [
            "/opt/homebrew/bin/deno",
            "/usr/local/bin/deno"
        ]) {
            return "deno:\(deno.path)"
        }
        if let node = find(names: ["node"], extraPaths: [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node"
        ]) {
            return "node:\(node.path)"
        }
        return nil
    }
}
