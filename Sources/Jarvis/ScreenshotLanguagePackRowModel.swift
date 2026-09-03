import Combine
import Foundation
import Translation

// 每行语言包的状态机。全部状态写入集中在 apply 方法并带代数守卫：
// 取消/重新下载后，任何旧任务的迟到写（prepare 完成、检测结果、失败标记）
// 都会因代数不匹配被丢弃 —— 取消的 UI 复位只发生在 cancelDownload() 本身，
// 绝不依赖框架会话是否及时中断。
//
// TranslationSession 无公开的"未安装对"构造，会话只能经 SwiftUI .translationTask 获得：
// 模型发布 sessionConfiguration 驱动行的 translationTask，行把到手的会话包装成
// LanguagePackSessionHandling 交回 handOver()；取消时置空 configuration 让 SwiftUI
// 中断会话任务，模型同时取消已交接的句柄与自身收尾任务，双保险
@MainActor
final class LanguagePackRowModel: ObservableObject {
    enum Phase: Equatable {
        case checking
        case supported
        case installed
        case unsupported
        case downloading
        case failed(String)
    }

    let target: ScreenshotTranslationLanguage
    let service: any LanguagePackService

    @Published private(set) var phase: Phase = .checking
    // 行视图 .translationTask 的绑定源；下载结束后与取消时均置空
    @Published private(set) var sessionConfiguration: TranslationSession.Configuration?
    // 会话通道尝试代数：SwiftUI 的 translationTask 只在 Configuration 值变化时派发新会话，
    // 取消后重试的 Configuration 与旧值 Equatable 相等会被跳过 —— 行视图用此代数做 .id()，
    // 每次发起下载都重建承载 translationTask 的视图，从"新挂载"状态保证必然派发一次
    @Published private(set) var channelGeneration = 0

    private var generation = 0
    private var pendingGeneration: Int?
    private var handler: (any LanguagePackSessionHandling)?
    private var workTask: Task<Void, Never>?

    init(target: ScreenshotTranslationLanguage, service: any LanguagePackService) {
        self.target = target
        self.service = service
    }

    var isBusy: Bool {
        phase == .checking || phase == .downloading
    }

    private var canStartDownload: Bool {
        switch phase {
        case .supported, .failed: true
        default: false
        }
    }

    // 重新检测：不打断下载中的行
    func refresh() async {
        guard phase != .downloading else { return }
        let g = beginGeneration()
        apply(.checking, ifGeneration: g)
        let resolved = await resolveStatus()
        apply(resolved, ifGeneration: g)
    }

    // 仅 supported / failed(重试) 可发起下载。设置 configuration 触发行视图 translationTask
    func startDownload() {
        guard canStartDownload else { return }
        let g = beginGeneration()
        pendingGeneration = g
        channelGeneration += 1
        apply(.downloading, ifGeneration: g)
        sessionConfiguration = ScreenshotAppleTranslation.configuration(
            source: ScreenshotLanguagePackProbe(target: target).source.localeLanguage,
            target: target
        )
    }

    // 会话到达（translationTask 交付）后由行视图调用；迟到的旧会话不启动任何工作
    func handOver(_ sessionHandler: any LanguagePackSessionHandling) {
        guard phase == .downloading, let g = pendingGeneration, handler == nil else { return }
        handler = sessionHandler
        pendingGeneration = nil
        workTask = Task { [weak self] in
            await self?.performDownload(handler: sessionHandler, generation: g)
        }
    }

    // 同步、幂等：立即复位 UI，不等待框架会话中断
    func cancelDownload() {
        guard phase == .downloading else { return }
        let g = beginGeneration()
        pendingGeneration = nil
        sessionConfiguration = nil
        workTask?.cancel()
        workTask = nil
        handler?.cancel()
        handler = nil
        apply(.checking, ifGeneration: g)
        Task { [weak self] in
            guard let self else { return }
            let resolved = await self.resolveStatus()
            self.apply(resolved, ifGeneration: g)
        }
    }

    // 视图离开时清理（不用 deinit：任务/句柄生命周期显式管理）
    func tearDown() {
        generation += 1
        pendingGeneration = nil
        sessionConfiguration = nil
        workTask?.cancel()
        workTask = nil
        handler?.cancel()
        handler = nil
    }

    private func performDownload(
        handler: any LanguagePackSessionHandling,
        generation g: Int
    ) async {
        do {
            try await handler.prepare()
            guard generation == g else { return }
            // prepare 成功通常即 installed；复核后按实际状态落态
            let resolved = await resolveStatus()
            apply(resolved, ifGeneration: g)
        } catch {
            guard generation == g else { return }
            if Self.isCancellation(error) { return }
            apply(.failed(message(for: error)), ifGeneration: g)
        }
        if generation == g {
            self.handler = nil
            sessionConfiguration = nil
        }
    }

    private func resolveStatus() async -> Phase {
        switch await service.status(for: target) {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        }
    }

    private func message(for error: Error) -> String {
        if let issue = error as? LanguagePackDownloadIssue {
            return issue.message
        }
        return error.localizedDescription
    }

    private func beginGeneration() -> Int {
        generation += 1
        return generation
    }

    private func apply(_ newPhase: Phase, ifGeneration g: Int) {
        guard generation == g else { return }
        phase = newPhase
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return (error as NSError).domain == NSCocoaErrorDomain
            && (error as NSError).code == NSUserCancelledError
    }
}
