import Foundation
import Translation

struct ScreenshotAppleTranslationJob: Sendable {
    let generation: Int
    let source: Locale.Language?
    let target: ScreenshotTranslationLanguage
    let blocks: [ScreenshotOCRBlock]
}

enum ScreenshotAppleTranslation {
    static func normalizedLanguage(_ language: Locale.Language) -> Locale.Language {
        let code = language.languageCode?.identifier.lowercased()
        switch code {
        case "zh":
            if language.script?.identifier == "Hant" {
                return Locale.Language(identifier: "zh-Hant")
            }
            return Locale.Language(identifier: "zh-Hans")
        case "en":
            return Locale.Language(identifier: "en-US")
        case "ja":
            return Locale.Language(identifier: "ja-JP")
        case "ko":
            return Locale.Language(identifier: "ko-KR")
        default:
            return language
        }
    }

    static func configuration(
        source: Locale.Language?,
        target: ScreenshotTranslationLanguage
    ) -> TranslationSession.Configuration {
        let normalizedSource = source.map(normalizedLanguage)
        if #available(macOS 26.4, *) {
            return TranslationSession.Configuration(
                source: normalizedSource,
                target: target.localeLanguage,
                preferredStrategy: .lowLatency
            )
        }
        return TranslationSession.Configuration(
            source: normalizedSource,
            target: target.localeLanguage
        )
    }

    static func installedSession(
        source: Locale.Language,
        target: ScreenshotTranslationLanguage
    ) -> TranslationSession {
        let normalizedSource = normalizedLanguage(source)
        if #available(macOS 26.4, *) {
            return TranslationSession(
                installedSource: normalizedSource,
                target: target.localeLanguage,
                preferredStrategy: .lowLatency
            )
        }
        return TranslationSession(
            installedSource: normalizedSource,
            target: target.localeLanguage
        )
    }

    static func requests(from blocks: [ScreenshotOCRBlock]) -> [TranslationSession.Request] {
        blocks.map { block in
            TranslationSession.Request(
                sourceText: block.text,
                clientIdentifier: block.id.uuidString
            )
        }
    }

    static func availability(
        source: Locale.Language?,
        sampleText: String,
        target: ScreenshotTranslationLanguage
    ) async -> LanguageAvailability.Status {
        let availability = languageAvailability()
        if let source {
            return await availability.status(
                from: normalizedLanguage(source),
                to: target.localeLanguage
            )
        }
        do {
            return try await availability.status(
                for: sampleText,
                to: target.localeLanguage
            )
        } catch {
            return .unsupported
        }
    }

    private static func languageAvailability() -> LanguageAvailability {
        if #available(macOS 26.4, *) {
            return LanguageAvailability(preferredStrategy: .lowLatency)
        }
        return LanguageAvailability()
    }
}
