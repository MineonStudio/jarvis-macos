import Combine
import Foundation
import Translation

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
    @Published private(set) var sessionConfiguration: TranslationSession.Configuration?
    /// SwiftUI skips `translationTask` when Configuration is Equatable-equal; bump
    /// this so cancel-then-retry remounts the view and gets a new session.
    @Published private(set) var channelGeneration = 0

    private var generation = 0
    private var pendingGeneration: Int?
    private var handler: (any LanguagePackSessionHandling)?

    init(target: ScreenshotTranslationLanguage, service: any LanguagePackService) {
        self.target = target
        self.service = service
    }

    var isBusy: Bool {
        phase == .checking || phase == .downloading
    }

    private var canStartDownload: Bool {
        switch phase {
        case .supported, .failed:
            true
        default:
            false
        }
    }

    func refresh() async {
        guard phase != .downloading else {
            return
        }
        let g = beginGeneration()
        apply(.checking, ifGeneration: g)
        let resolved = await resolveStatus()
        apply(resolved, ifGeneration: g)
    }

    func startDownload() {
        guard canStartDownload else {
            return
        }
        let g = beginGeneration()
        pendingGeneration = g
        channelGeneration += 1
        apply(.downloading, ifGeneration: g)
        sessionConfiguration = ScreenshotAppleTranslation.configuration(
            source: ScreenshotLanguagePackProbe(target: target).source.localeLanguage,
            target: target
        )
    }

    /// Await inside `.translationTask` so `TranslationSession` is not used after
    /// that view/task ends.
    func consumeSession(_ sessionHandler: any LanguagePackSessionHandling) async {
        guard phase == .downloading, let g = pendingGeneration, handler == nil else {
            return
        }
        handler = sessionHandler
        pendingGeneration = nil
        await performDownload(handler: sessionHandler, generation: g)
    }

    func cancelDownload() {
        guard phase == .downloading else {
            return
        }
        let g = beginGeneration()
        pendingGeneration = nil
        sessionConfiguration = nil
        handler?.cancel()
        handler = nil
        apply(.checking, ifGeneration: g)
        Task { [weak self] in
            guard let self else {
                return
            }
            let resolved = await self.resolveStatus()
            self.apply(resolved, ifGeneration: g)
        }
    }

    func tearDown() {
        generation += 1
        pendingGeneration = nil
        sessionConfiguration = nil
        handler?.cancel()
        handler = nil
    }

    private func performDownload(
        handler: any LanguagePackSessionHandling,
        generation g: Int
    ) async {
        do {
            try await handler.prepare()
            guard generation == g else {
                return
            }
            let resolved = await resolveStatus()
            apply(resolved, ifGeneration: g)
        } catch {
            guard generation == g else {
                return
            }
            if Self.isCancellation(error) {
                return
            }
            apply(.failed(message(for: error)), ifGeneration: g)
        }
        if generation == g {
            self.handler = nil
            sessionConfiguration = nil
        }
    }

    private func resolveStatus() async -> Phase {
        switch await service.status(for: target) {
        case .installed:
            .installed
        case .supported:
            .supported
        case .unsupported:
            .unsupported
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
        guard generation == g else {
            return
        }
        phase = newPhase
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        return (error as NSError).domain == NSCocoaErrorDomain
            && (error as NSError).code == NSUserCancelledError
    }
}
