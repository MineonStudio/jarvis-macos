import Foundation
import Translation

enum LanguagePackSupport: Equatable, Sendable {
    case installed
    case supported
    case unsupported
}

// 可读下载失败（而非框架错误）：文案直接展示在行内
struct LanguagePackDownloadIssue: LocalizedError, Equatable, Sendable {
    let message: String

    var errorDescription: String? {
        message
    }
}

// 下载会话句柄：由行视图的 translationTask 把 SwiftUI 交付的 TranslationSession
// 包装成此协议后交给模型（TranslationSession 无公开的"未安装对"构造，只能经 SwiftUI 获取）
protocol LanguagePackSessionHandling: Sendable {
    func prepare() async throws
    func cancel()
}

// 状态检测服务：无内部可变状态的值类型
protocol LanguagePackService: Sendable {
    func status(for target: ScreenshotTranslationLanguage) async -> LanguagePackSupport
}

struct SystemLanguagePackService: LanguagePackService {
    func status(for target: ScreenshotTranslationLanguage) async -> LanguagePackSupport {
        let probe = ScreenshotLanguagePackProbe(target: target)
        let status = await ScreenshotAppleTranslation.availability(
            source: probe.source.localeLanguage,
            sampleText: probe.sampleText,
            target: target
        )
        switch status {
        case .installed: return .installed
        case .supported: return .supported
        default: return .unsupported
        }
    }
}

// TranslationSession 非 Sendable、且 cancel/prepare 在线程间调用未标注，按项目 v5 语言模式放宽
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
            // 会话被取消（含系统侧已取消状态）统一归为取消语义，由模型按代数守卫丢弃
            if TranslationError.alreadyCancelled ~= error {
                throw CancellationError()
            }
            throw error
        }
    }

    private func prepareCore() async throws {
        // 幂等短路：已安装直接成功（重试场景下 OS 后台可能已悄悄装完）
        if await SystemLanguagePackService().status(for: target) == .installed {
            return
        }

        // 离线/系统策略禁止下载时提前给出可读提示，避免笼统"下载失败"
        guard session.canRequestDownloads else {
            throw LanguagePackDownloadIssue(message: "系统当前无法下载语言包，可在首次截图翻译时由系统自动下载")
        }

        if #available(macOS 26.4, *) {
            // 主路径：显式触发下载并等待就绪
            try await session.prepareTranslation()
        } else {
            // 26.0–26.3 回退：探针翻译本身会触发并等待系统下载完成
            let request = TranslationSession.Request(
                sourceText: ScreenshotLanguagePackProbe(target: target).sampleText,
                clientIdentifier: Self.clientIdentifier
            )
            _ = try await session.translations(from: [request])
        }

        guard await SystemLanguagePackService().status(for: target) == .installed else {
            throw LanguagePackDownloadIssue(message: "语言包未能完成安装，请重试")
        }
    }

    func cancel() {
        session.cancel()
    }

    private static let clientIdentifier = "jarvis-language-pack-probe"
}
