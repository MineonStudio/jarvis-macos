import Foundation

extension ScreenshotTranslationLanguage {
    // 设置页语言包检测/下载的目标及顺序。繁体中文不在此列：它仍是编辑器可选目标，
    // 首次使用时由系统自动按需下载
    static let packTargets: [ScreenshotTranslationLanguage] = [
        .simplifiedChinese,
        .english,
        .japanese,
        .korean,
        .spanish
    ]
}

// 语言包检测/下载以"简体中文 ↔ 目标语言"为代表对（中文用户最常见场景）；
// 中文本身作目标时用英语作源。其他语言对按需在首次翻译时由系统自动下载。
struct ScreenshotLanguagePackProbe: Equatable, Sendable {
    let target: ScreenshotTranslationLanguage
    let source: ScreenshotTranslationLanguage
    let sampleText: String

    init(target: ScreenshotTranslationLanguage) {
        switch target {
        case .simplifiedChinese, .traditionalChinese:
            source = .english
            sampleText = "The quick brown fox jumps over the lazy dog."
        case .english, .japanese, .korean, .spanish:
            source = .simplifiedChinese
            sampleText = "这是一段用于准备系统翻译语言包的示例文本。"
        }
        self.target = target
    }
}
