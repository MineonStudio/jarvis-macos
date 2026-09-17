import Foundation

enum SkillID: String, CaseIterable, Hashable, Identifiable {
    case screenshot
    case clipboard
    case windowLayout
    case resume
    case wallpaper
    case meetingNotes
    case rss

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshot: "截图技能"
        case .clipboard: "剪贴板技能"
        case .windowLayout: "窗口布局技能"
        case .resume: "简历制作技能"
        case .wallpaper: "桌面壁纸技能"
        case .meetingNotes: "会议记录技能"
        case .rss: "RSS 订阅技能"
        }
    }

    var navigationTitle: String {
        switch self {
        case .screenshot: "截图"
        case .clipboard: "剪贴板"
        case .windowLayout: "窗口布局"
        case .resume: "简历制作"
        case .wallpaper: "桌面壁纸"
        case .meetingNotes: "会议记录"
        case .rss: "订阅"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: "viewfinder"
        case .clipboard: "clipboard"
        case .windowLayout: "macwindow.on.rectangle"
        case .resume: "doc.text.magnifyingglass"
        case .wallpaper: "photo.on.rectangle.angled"
        case .meetingNotes: "waveform.and.person.filled"
        case .rss: "dot.radiowaves.up.forward"
        }
    }
}
