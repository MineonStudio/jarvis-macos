import Foundation

extension ScreenshotEditorModel {
    var renderedTranslationBlocks: [ScreenshotTranslationRenderBlock] {
        guard translationVisible else { return [] }
        let selection = selectionRect ?? CGRect(origin: .zero, size: canvasSize)
        return translationBlocks.map { block in
            let bounds = ScreenshotTranslationGeometry.canvasBounds(
                for: block.normalizedBounds,
                in: selection
            )
            return ScreenshotTranslationRenderBlock(
                id: block.id,
                sourceText: block.sourceText,
                translatedText: block.translatedText,
                bounds: bounds,
                confidence: block.confidence
            )
        }
    }

    func enterTranslationMode() {
        selectedTool = nil
        selectedAnnotationID = nil
        translationMode = true
    }

    func startTranslation() {
        guard !translationState.isRunning else { return }
        let configuration = ScreenshotTranslationConfiguration.load()
        guard configuration.isConfigured else {
            translationState = .failed(AIAPIError.missingConfiguration.localizedDescription)
            return
        }

        translationTask?.cancel()
        translationGeneration += 1
        let generation = translationGeneration
        translationBlocks.removeAll()
        translationVisible = true
        translationState = .recognizing
        let sourceData = originalOutputData
        let targetLanguage = translationTargetLanguage

        translationTask = Task { [weak self] in
            do {
                let service = ScreenshotTranslationService()
                let ocrBlocks = try await service.recognizeText(in: sourceData)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self, self.translationGeneration == generation else { return }
                    self.translationState = .translating(completed: 0, total: ocrBlocks.count)
                }
                let editor = self
                let translatedBlocks = try await service.translate(
                    ocrBlocks,
                    targetLanguage: targetLanguage,
                    configuration: configuration,
                    onProgress: { completed, total in
                        Task { @MainActor [weak editor] in
                            guard let editor, editor.translationGeneration == generation else { return }
                            editor.translationState = .translating(completed: completed, total: total)
                        }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self, self.translationGeneration == generation else { return }
                    self.translationBlocks = translatedBlocks
                    self.translationState = .completed(count: translatedBlocks.count)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self, self.translationGeneration == generation else { return }
                    if self.translationState.isRunning {
                        self.translationState = .idle
                    }
                }
            } catch {
                if Self.isCancellation(error) {
                    await MainActor.run {
                        guard let self, self.translationGeneration == generation else { return }
                        if self.translationState.isRunning {
                            self.translationState = .idle
                        }
                    }
                    return
                }
                await MainActor.run {
                    guard let self, self.translationGeneration == generation else { return }
                    self.translationState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelTranslation() {
        translationGeneration += 1
        translationTask?.cancel()
        translationTask = nil
        if translationState.isRunning {
            translationState = .idle
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    func clearTranslation() {
        cancelTranslation()
        translationBlocks.removeAll()
        translationVisible = true
        translationState = .idle
    }
}
