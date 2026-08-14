import Foundation

enum SkillID: String, CaseIterable, Hashable, Identifiable {
    case screenshot
    case clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshot: return "截图技能"
        case .clipboard: return "剪贴板技能"
        }
    }

    var icon: String {
        switch self {
        case .screenshot: return "viewfinder"
        case .clipboard: return "clipboard"
        }
    }

}
