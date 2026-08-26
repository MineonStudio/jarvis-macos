import Foundation

enum SkillID: String, CaseIterable, Hashable, Identifiable {
    case screenshot
    case clipboard
    case windowLayout

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshot: "截图技能"
        case .clipboard: "剪贴板技能"
        case .windowLayout: "窗口布局技能"
        }
    }

    var navigationTitle: String {
        switch self {
        case .screenshot: "截图"
        case .clipboard: "剪贴板"
        case .windowLayout: "窗口布局"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: "viewfinder"
        case .clipboard: "clipboard"
        case .windowLayout: "macwindow.on.rectangle"
        }
    }
}
