import Foundation

/// A visual text region returned by the vision model.
///
/// `boundingBox` uses normalized coordinates with an origin in the image's
/// top-left corner. Keeping this coordinate system in the model response
/// means the renderer can cover the exact region that was identified without
/// deriving a new position from the translated string.
struct ScreenshotTranslationBlock: Equatable, Sendable {
    let sourceText: String
    let translatedText: String
    let boundingBox: CGRect
}

struct ScreenshotTranslationResult: Equatable, Sendable {
    let blocks: [ScreenshotTranslationBlock]

    var translatedText: String {
        blocks.map(\.translatedText).joined(separator: "\n")
    }
}

enum ScreenshotTranslationLanguage: String, CaseIterable, Codable, Identifiable {
    case chinese = "中文"
    case english = "English"
    case japanese = "日本語"
    case korean = "한국어"
    case french = "Français"
    case spanish = "Español"

    var id: String {
        rawValue
    }
}

enum ScreenshotTranslationState: Equatable {
    case idle
    case translating
    case success(String)
    case failed(String)
}
