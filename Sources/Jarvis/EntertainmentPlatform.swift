import Foundation

enum EntertainmentPlatform: String, CaseIterable, Hashable, Identifiable {
    case x
    case youtube
    case tiktok
    case twitch

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .x: "X"
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .twitch: "Twitch"
        }
    }

    var iconResourceName: String {
        rawValue
    }

    var iconResourceExtension: String {
        "svg"
    }

    var systemImage: String {
        switch self {
        case .x: "x.circle"
        case .youtube: "play.rectangle.fill"
        case .tiktok: "music.note"
        case .twitch: "video.fill"
        }
    }

    var url: URL {
        switch self {
        case .x:
            URL(string: "https://x.com/")!
        case .youtube:
            URL(string: "https://www.youtube.com/")!
        case .tiktok:
            URL(string: "https://www.tiktok.com/")!
        case .twitch:
            URL(string: "https://www.twitch.tv/")!
        }
    }

    var allowedHosts: Set<String> {
        switch self {
        case .x:
            ["x.com", "twitter.com"]
        case .youtube:
            ["youtube.com", "youtu.be", "accounts.google.com", "accounts.youtube.com"]
        case .tiktok:
            ["tiktok.com", "tiktokv.com"]
        case .twitch:
            ["twitch.tv"]
        }
    }

    var webPlatform: JarvisWebPlatformDescriptor {
        JarvisWebPlatformDescriptor(
            id: "entertainment.\(rawValue)",
            title: title,
            url: url,
            allowedHosts: allowedHosts
        )
    }

    func allowsHost(_ host: String) -> Bool {
        JarvisWebHostAllowlist.contains(host, in: allowedHosts)
    }
}
