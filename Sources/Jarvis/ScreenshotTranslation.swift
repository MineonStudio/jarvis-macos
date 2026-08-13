import Foundation

enum ScreenshotTranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case chinese = "中文"
    case english = "English"
    case japanese = "日本語"
    case korean = "한국어"
    case french = "Français"
    case spanish = "Español"

    var id: String { rawValue }
}

enum ScreenshotTranslationState: Equatable {
    case idle
    case translating
    case reviewingOCR(String)
    case success(String)
    case failed(String)
}
