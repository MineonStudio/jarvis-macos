import AppKit
import Foundation
import Translation

enum LanguagePackSupport: Equatable, Sendable {
    case installed
    case supported
    case unsupported
}

struct LanguagePackDownloadIssue: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

protocol LanguagePackSessionHandling: Sendable {
    func prepare() async throws
    func cancel()
}

protocol LanguagePackService: Sendable {
    func status(for target: ScreenshotTranslationLanguage) async -> LanguagePackSupport
}

struct SystemLanguagePackService: LanguagePackService {
    @MainActor
    static func openLanguageSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Localization-Settings.extension"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    func status(for target: ScreenshotTranslationLanguage) async -> LanguagePackSupport {
        let probe = ScreenshotLanguagePackProbe(target: target)
        let status = await ScreenshotAppleTranslation.availability(
            source: probe.source.localeLanguage,
            sampleText: probe.sampleText,
            target: target
        )
        switch status {
        case .installed:
            return .installed
        case .supported:
            return .supported
        default:
            return .unsupported
        }
    }
}

/// TranslationSession is not Sendable; prepare/cancel cross isolation.
final class SystemLanguagePackSessionHandler: LanguagePackSessionHandling, @unchecked Sendable {
    let target: ScreenshotTranslationLanguage
    let session: TranslationSession

    init(target: ScreenshotTranslationLanguage, session: TranslationSession) {
        self.target = target
        self.session = session
    }

    func prepare() async throws {
        do {
            try await prepareCore()
        } catch {
            if TranslationError.alreadyCancelled ~= error {
                throw CancellationError()
            }
            throw error
        }
    }

    private func prepareCore() async throws {
        if await SystemLanguagePackService().status(for: target) == .installed {
            return
        }

        guard session.canRequestDownloads else {
            throw LanguagePackDownloadIssue(message: "系统当前无法下载语言包，可在首次截图翻译时由系统自动下载")
        }

        if #available(macOS 26.4, *) {
            try await session.prepareTranslation()
        } else {
            let request = TranslationSession.Request(
                sourceText: ScreenshotLanguagePackProbe(target: target).sampleText,
                clientIdentifier: Self.clientIdentifier
            )
            _ = try await session.translations(from: [request])
        }

        // prepareTranslation 返回后系统资产未必已经落盘，立刻探一次就判失败会让用户
        // 看到「未能完成安装，请重试」——而他真的重试就是对同一个语言对再发一次下载。
        // 给几秒钟的收敛时间。
        for _ in 0 ..< 5 {
            if await SystemLanguagePackService().status(for: target) == .installed {
                return
            }
            try Task.checkCancellation()
            try? await Task.sleep(for: .seconds(2))
        }
        throw LanguagePackDownloadIssue(message: "语言包仍在后台安装，稍后重新打开设置即可更新状态")
    }

    func cancel() {
        session.cancel()
    }

    private static let clientIdentifier = "jarvis-language-pack-probe"
}
