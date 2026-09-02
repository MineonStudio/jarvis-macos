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

        dailyQuoteGeneration += 1
        let generation = dailyQuoteGeneration
        dailyQuoteTask = Task { @MainActor [weak self] in
            defer {
                if self?.dailyQuoteGeneration == generation {
                    self?.dailyQuoteTask = nil
                }
            }

            do {
                let configuration = AIAPIConfiguration.load()
                guard !Task.isCancelled, let self, self.dailyQuoteGeneration == generation else { return }

                guard configuration.isConfigured else { return }
                if !force, cachedQuote?.source == .ai {
                    self.dailyQuote = cachedQuote!
                    return
                }

                let service = self.dailyQuoteService
                let quote = try await service.generate(for: dayKey, configuration: configuration)
                guard !Task.isCancelled, self.dailyQuoteGeneration == generation else { return }
                self.dailyQuote = quote
                self.dailyQuoteStore.save(quote, for: dayKey)
            } catch is CancellationError {
                return
            } catch {
                if force {
                    self?.showToast("每日语录生成失败：\(error.localizedDescription)")
                }
            }
        }
    }
}
