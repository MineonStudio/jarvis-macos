import Foundation

enum EntertainmentPlatform: String, CaseIterable, Hashable, Identifiable {
    case x
    case youtube
    case tiktok
    case twitch
    case bilibili

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .x: "X"
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .twitch: "Twitch"
        case .bilibili: "哔哩哔哩"
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
        case .bilibili: "tv.fill"
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
        case .bilibili:
            URL(string: "https://www.bilibili.com/")!
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
            // id/player/m 等均为 twitch.tv 子域，后缀匹配自动覆盖
            ["twitch.tv"]
        case .bilibili:
            ["bilibili.com", "b23.tv"]
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
