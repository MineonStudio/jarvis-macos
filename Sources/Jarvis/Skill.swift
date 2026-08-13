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

    var subtitle: String {
        switch self {
        case .screenshot: return "框选、编辑、翻译与复制"
        case .clipboard: return "记录、搜索与恢复复制内容"
        }
    }
}
