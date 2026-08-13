import AppKit

enum JarvisAppVersion {
    static let repositoryURL = URL(string: "https://github.com/MineonStudio/jarvis-macos")!
    static let releasesURL = URL(string: "https://github.com/MineonStudio/jarvis-macos/releases")!

    private static let fallbackShortVersion = "0.4.6"
    private static let fallbackBuild = "70"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackShortVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? fallbackBuild
    }

    static var displayName: String {
        "v\(shortVersion) (构建 \(build))"
    }
}

enum JarvisUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

struct JarvisUpdateService {
    func checkForLatestRelease() async throws -> (version: String, url: URL) {
        let endpoint = URL(string: "https://api.github.com/repos/MineonStudio/jarvis-macos/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/jarvis-macos", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else {
            throw URLError(.resourceUnavailable)
        }
        return (release.tagName, release.htmlURL)
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = versionParts(remote)
        let localParts = versionParts(local)
        guard !remoteParts.isEmpty, !localParts.isEmpty else { return remote != local }

        for index in 0..<max(remoteParts.count, localParts.count) {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    private func versionParts(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .compactMap { Int($0) }
    }
}
