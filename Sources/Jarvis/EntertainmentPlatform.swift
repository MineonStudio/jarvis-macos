import Foundation

enum EntertainmentPlatform: String, CaseIterable, Hashable, Identifiable {
    case x
    case youtube
    case tiktok

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .x: "X"
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        }
    }

    var systemImage: String {
        switch self {
        case .x: "x.circle"
        case .youtube: "play.rectangle.fill"
        case .tiktok: "music.note"
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
