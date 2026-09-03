import Foundation

extension ScreenshotTranslationLanguage {
    /// Settings download list. Traditional Chinese stays editor-only; the system
    /// fetches that pair on first translation.
    static let packTargets: [ScreenshotTranslationLanguage] = [
        .simplifiedChinese,
        .english,
        .japanese,
        .korean,
        .spanish
    ]
}

/// Representative pair for pack detection/download (`zh-Hans` ↔ target).
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
