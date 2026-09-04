import Foundation
import Translation

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

        translationTask?.cancel()
        resumeAppleTranslationJob(.failure(CancellationError()))
        translationGeneration += 1
        let generation = translationGeneration
        translationBlocks.removeAll()
        appleTranslationSourceBlocks.removeAll()
        translationVisible = true
        translationState = .recognizing
        pendingAppleTranslationJob = nil
        appleTranslationConfiguration = nil
        let sourceData = originalOutputData
        let targetLanguage = translationTargetLanguage

        translationTask = Task { [weak self] in
            await self?.runTranslation(
                generation: generation,
                sourceData: sourceData,
                targetLanguage: targetLanguage
            )
        }
    }

    func cancelTranslation() {
        translationGeneration += 1
        translationTask?.cancel()
        translationTask = nil
        pendingAppleTranslationJob = nil
        appleTranslationSourceBlocks.removeAll()
        appleTranslationConfiguration = nil
        resumeAppleTranslationJob(.failure(CancellationError()))
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

    nonisolated func consumeAppleTranslationSession(_ session: TranslationSession) async {
        let job = await takePendingAppleTranslationJob()
        guard let job else { return }
        do {
            let requests = ScreenshotAppleTranslation.requests(from: job.blocks)
            for try await response in session.translate(batch: requests) {
                await applyAppleTranslationResponse(response, generation: job.generation)
            }
            await completeAppleTranslationJob(generation: job.generation)
        } catch {
            await failAppleTranslationJob(error, generation: job.generation)
        }
    }

    private func runTranslation(
        generation: Int,
        sourceData: Data,
        targetLanguage: ScreenshotTranslationLanguage
    ) async {
        do {
            let service = ScreenshotTranslationService()
            let ocrBlocks = try await service.recognizeText(in: sourceData)
            try Task.checkCancellation()
            guard translationGeneration == generation else { return }

            let plan = service.classify(ocrBlocks, targetLanguage: targetLanguage)
            try await translate(
                plan: plan,
                targetLanguage: targetLanguage,
                generation: generation
            )
        } catch is CancellationError {
            resetRunningTranslationIfNeeded(generation: generation)
        } catch {
            if Self.isCancellation(error) {
                resetRunningTranslationIfNeeded(generation: generation)
                return
            }
            guard translationGeneration == generation else { return }
            translationState = .failed(error.localizedDescription)
        }
    }

    private func translate(
        plan: ScreenshotTranslationPlan,
        targetLanguage: ScreenshotTranslationLanguage,
        generation: Int
    ) async throws {
        let total = plan.translatableCount
        translationState = .translating(completed: 0, total: total)
        guard total > 0 else {
            translationState = .completed(count: 0)
            return
        }

        var completed = 0
        var lastError: Error?
        for group in plan.groups {
            try Task.checkCancellation()
            guard translationGeneration == generation else { return }
            do {
                try await translate(
                    group: group,
                    targetLanguage: targetLanguage,
                    generation: generation
                )
                completed += group.blocks.count
                guard translationGeneration == generation else { return }
                translationState = .translating(completed: min(completed, total), total: total)
            } catch {
                if Task.isCancelled || Self.isCancellation(error) {
                    throw error
                }
                lastError = error
            }
        }

        guard translationGeneration == generation else { return }
        if translationBlocks.isEmpty {
            throw lastError ?? ScreenshotTranslationError.noTextFound
        }
        translationState = .completed(count: translationBlocks.count)
    }

    private func translate(
        group: ScreenshotTranslationLanguageGroup,
        targetLanguage: ScreenshotTranslationLanguage,
        generation: Int
    ) async throws {
        let sampleText = group.blocks.map(\.text).joined(separator: "\n")
        let status = await ScreenshotAppleTranslation.availability(
            source: group.source,
            sampleText: sampleText,
            target: targetLanguage
        )

        if status == .installed, let source = group.source {
            do {
                try await translateWithInstalledApple(
                    group: group,
                    source: source,
                    targetLanguage: targetLanguage,
                    generation: generation
                )
                return
            } catch {
                if Task.isCancelled || Self.isCancellation(error) {
                    throw error
                }
            }
        }

        if status == .installed || status == .supported {
            try await translateWithAppleDownload(
                group: group,
                targetLanguage: targetLanguage,
                generation: generation
            )
            return
        }

        throw ScreenshotTranslationError.unsupportedLanguagePair
    }

    private func translateWithInstalledApple(
        group: ScreenshotTranslationLanguageGroup,
        source: Locale.Language,
        targetLanguage: ScreenshotTranslationLanguage,
        generation: Int
    ) async throws {
        rememberTranslationSources(group.blocks)
        let session = ScreenshotAppleTranslation.installedSession(
            source: source,
            target: targetLanguage
        )
        let requests = ScreenshotAppleTranslation.requests(from: group.blocks)
        for try await response in session.translate(batch: requests) {
            try Task.checkCancellation()
            applyAppleTranslationResponse(response, generation: generation)
        }
    }

    private func translateWithAppleDownload(
        group: ScreenshotTranslationLanguageGroup,
        targetLanguage: ScreenshotTranslationLanguage,
        generation: Int
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            rememberTranslationSources(group.blocks)
            pendingAppleTranslationJob = ScreenshotAppleTranslationJob(
                generation: generation,
                source: group.source,
                target: targetLanguage,
                blocks: group.blocks
            )
            appleTranslationJobContinuation = continuation
            updateAppleTranslationConfiguration(
                source: group.source,
                target: targetLanguage
            )
        }
    }

    private func updateAppleTranslationConfiguration(
        source: Locale.Language?,
        target: ScreenshotTranslationLanguage
    ) {
        if var configuration = appleTranslationConfiguration {
            configuration.source = source.map(ScreenshotAppleTranslation.normalizedLanguage)
            configuration.target = target.localeLanguage
            if #available(macOS 26.4, *) {
                configuration.preferredStrategy = .lowLatency
            }
            configuration.invalidate()
            appleTranslationConfiguration = configuration
        } else {
            appleTranslationConfiguration = ScreenshotAppleTranslation.configuration(
                source: source,
                target: target
            )
        }
    }

    private func takePendingAppleTranslationJob() -> ScreenshotAppleTranslationJob? {
        let job = pendingAppleTranslationJob
        pendingAppleTranslationJob = nil
        return job
    }

    private func applyAppleTranslationResponse(
        _ response: TranslationSession.Response,
        generation: Int
    ) {
        guard translationGeneration == generation,
              let identifier = response.clientIdentifier,
              let blockID = UUID(uuidString: identifier)
        else { return }
        let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translatedText.isEmpty else { return }

        if let index = translationBlocks.firstIndex(where: { $0.id == blockID }) {
            translationBlocks[index].translatedText = translatedText
            return
        }

        guard let sourceBlock = appleTranslationSourceBlocks[blockID] else { return }
        upsertTranslationBlock(
            ScreenshotTranslationBlock(
                id: sourceBlock.id,
                sourceText: sourceBlock.text,
                translatedText: translatedText,
                normalizedBounds: sourceBlock.normalizedBounds,
                confidence: sourceBlock.confidence
            )
        )
    }

    private func rememberTranslationSources(_ blocks: [ScreenshotOCRBlock]) {
        for block in blocks {
            appleTranslationSourceBlocks[block.id] = block
        }
    }

    private func upsertTranslationBlock(_ block: ScreenshotTranslationBlock) {
        if let index = translationBlocks.firstIndex(where: { $0.id == block.id }) {
            translationBlocks[index] = block
        } else {
            translationBlocks.append(block)
        }
    }

    private func completeAppleTranslationJob(generation: Int) {
        guard translationGeneration == generation else {
            resumeAppleTranslationJob(.failure(CancellationError()))
            return
        }
        resumeAppleTranslationJob(.success(()))
    }

    private func failAppleTranslationJob(_ error: Error, generation: Int) {
        guard translationGeneration == generation else {
            resumeAppleTranslationJob(.failure(CancellationError()))
            return
        }
        resumeAppleTranslationJob(.failure(error))
    }

    private func resumeAppleTranslationJob(_ result: Result<Void, Error>) {
        guard let continuation = appleTranslationJobContinuation else { return }
        appleTranslationJobContinuation = nil
        continuation.resume(with: result)
    }

    private func resetRunningTranslationIfNeeded(generation: Int) {
        guard translationGeneration == generation, translationState.isRunning else { return }
        translationState = .idle
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
