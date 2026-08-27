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
        guard translationConfiguration.isConfigured else {
            translationState = .failed(AIAPIError.missingConfiguration.localizedDescription)
            return
        }

        translationTask?.cancel()
        translationBlocks.removeAll()
        translationVisible = true
        translationState = .recognizing
        let sourceData = originalOutputData
        let targetLanguage = translationTargetLanguage
        let configuration = translationConfiguration

        translationTask = Task { [weak self] in
            do {
                let service = ScreenshotTranslationService()
                let ocrBlocks = try await service.recognizeText(in: sourceData)
                try Task.checkCancellation()
                await MainActor.run {
                    self?.translationState = .translating(completed: 0, total: ocrBlocks.count)
                }
                let translatedBlocks = try await service.translate(
                    ocrBlocks,
                    targetLanguage: targetLanguage,
                    configuration: configuration
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self?.translationBlocks = translatedBlocks
                    self?.translationState = .completed(count: translatedBlocks.count)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.translationState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelTranslation() {
        translationTask?.cancel()
        translationTask = nil
        if translationState.isRunning {
            translationState = .idle
        }
    }

    func clearTranslation() {
        cancelTranslation()
        translationBlocks.removeAll()
        translationVisible = true
        translationState = .idle
    }
}
