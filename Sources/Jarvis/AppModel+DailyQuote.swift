import Foundation

extension AppModel {
    func refreshDailyQuote(force: Bool = false) {
        let dayKey = DailyQuote.dayKey()
        let cachedQuote = dailyQuoteStore.load(for: dayKey)
        let hasConfiguredAPI = screenshotTranslationAPIKeyConfigured
            && !screenshotTranslationEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !screenshotTranslationModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let fallbackQuote = cachedQuote?.source == .builtIn ? cachedQuote! : DailyQuote.builtIn()

        dailyQuoteTask?.cancel()
        dailyQuote = hasConfiguredAPI ? (cachedQuote ?? fallbackQuote) : fallbackQuote
        if cachedQuote == nil {
            dailyQuoteStore.save(fallbackQuote, for: dayKey)
        }

        guard hasConfiguredAPI else { return }

        dailyQuoteTask = Task { @MainActor [weak self] in
            defer {
                self?.dailyQuoteTask = nil
            }

            do {
                let configuration = await Task.detached(priority: .utility) {
                    AIAPIConfiguration.load()
                }.value
                guard !Task.isCancelled, let self else { return }

                guard configuration.isConfigured else { return }
                if !force, cachedQuote?.source == .ai {
                    self.dailyQuote = cachedQuote!
                    return
                }

                let service = self.dailyQuoteService
                let quote = try await service.generate(for: dayKey, configuration: configuration)
                guard !Task.isCancelled else { return }
                self.dailyQuote = quote
                self.dailyQuoteStore.save(quote, for: dayKey)
            } catch {
                // Keep the already visible built-in or cached quote on failure.
            }
        }
    }
}
