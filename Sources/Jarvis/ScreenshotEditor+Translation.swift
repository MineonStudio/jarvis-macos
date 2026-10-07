import Foundation
import Translation

extension ScreenshotEditorModel {
    /// 重新算一遍用于渲染的译文块。
    ///
    /// 这段是 O(块数) 的排版计算——字号收敛循环里是上万次文本测量——所以不能挂在
    /// 视图 body 上：那样每次拖动、每个 `@Published` 变化都会重跑一遍。现在只在
    /// 真正影响排版的输入变化时重算（见各属性的 `didSet`），并且同一轮里的连续变化
    /// 合并成一次。
    func scheduleRenderedTranslationBlocksRefresh() {
        guard !isTranslationLayoutRefreshScheduled else { return }
        isTranslationLayoutRefreshScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            isTranslationLayoutRefreshScheduled = false
            refreshRenderedTranslationBlocks()
        }
    }

    func refreshRenderedTranslationBlocks() {
        let updated = Self.makeRenderedTranslationBlocks(
            translationVisible: translationVisible,
            translationSourceRect: translationSourceRect,
            selectionRect: selectionRect,
            canvasSize: canvasSize,
            translationBlocks: translationBlocks
        )
        // 拖动选区时每个鼠标事件都会走到这里，而结果往往一模一样；`@Published`
        // 每次赋值都会再发一次通知，把工具栏的重排也算进来。内容没变就别发。
        guard updated != renderedTranslationBlocks else { return }
        renderedTranslationBlocks = updated
    }

    private static func makeRenderedTranslationBlocks(
        translationVisible: Bool,
        translationSourceRect: CGRect?,
        selectionRect: CGRect?,
        canvasSize: CGSize,
        translationBlocks: [ScreenshotTranslationBlock]
    ) -> [ScreenshotTranslationRenderBlock] {
        guard translationVisible else { return [] }
        let selection = translationSourceRect
            ?? selectionRect
            ?? CGRect(origin: .zero, size: canvasSize)
        let rawBlocks = translationBlocks.map { block in
            let bounds = ScreenshotTranslationGeometry.canvasBounds(
                for: block.normalizedBounds,
                in: selection
            )
            let sourceLines = block.sourceLines.map { line in
                ScreenshotTranslationLine(
                    text: line.text,
                    bounds: ScreenshotTranslationGeometry.canvasBounds(
                        for: line.bounds,
                        in: selection
                    ),
                    lineHeight: line.lineHeight * selection.height
                )
            }
            return ScreenshotTranslationRenderBlock(
                id: block.id,
                sourceText: block.sourceText,
                translatedText: block.translatedText,
                bounds: bounds,
                confidence: block.confidence,
                sourceLineHeight: block.lineHeight * selection.height,
                sourceLines: sourceLines
            )
        }
        return ScreenshotTranslationLayout.apply(
            to: rawBlocks,
            canvasSize: canvasSize,
            translationRegion: selection
        )
    }

    func enterTranslationMode() {
        // #11：和 selectTool 一致，先把正在输入的文字草稿提交，
        // 再清工具/选中态，避免草稿收尾路径不一致。
        commitTextEditing()
        selectedTool = nil
        selectedAnnotationID = nil
        translationMode = true
    }

    /// 与其它工具一致：再点一次翻译图标就退出，二级栏跟着收起。
    /// 这里不动已经完成的翻译结果，也不打断进行中的任务。
    func exitTranslationMode() {
        guard translationMode else { return }
        translationMode = false
    }

    /// 点翻译图标只开关二级栏，不开始翻译。开始和重跑都走二级栏上的按钮。
    func toggleTranslationMode() {
        if translationMode {
            exitTranslationMode()
        } else {
            enterTranslationMode()
        }
    }

    /// 还没翻过是「开始翻译」，一旦进入识别或已经有译文就改成「重新翻译」。
    var translationActionTitle: String {
        switch translationState {
        case .idle where translationBlocks.isEmpty:
            "开始翻译"
        default:
            "重新翻译"
        }
    }

    func startTranslation() {
        guard !translationState.isRunning else { return }

        translationTask?.cancel()
        resumeAppleTranslationJob(.failure(CancellationError()))
        translationGeneration += 1
        let generation = translationGeneration
        translationBlocks.removeAll()
        appleTranslationSourceBlocks.removeAll()
        translationProgress = nil
        translationVisible = true
        translationState = .recognizing
        pendingAppleTranslationJob = nil
        appleTranslationConfiguration = nil
        let sourceRect = selectionRect ?? CGRect(origin: .zero, size: canvasSize)
        guard let sourceData = translationSourceData(for: selectionRect) else {
            translationSourceRect = nil
            translationState = .failed("无法准备当前翻译选区")
            return
        }
        translationSourceRect = sourceRect
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
        translationProgress = nil
        appleTranslationConfiguration = nil
        resumeAppleTranslationJob(.failure(CancellationError()))
        if translationState.isRunning {
            translationState = .idle
        }
    }

    func clearTranslation() {
        cancelTranslation()
        translationBlocks.removeAll()
        translationSourceRect = nil
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

    func invalidateCachedOCR() {
        cachedOCR = nil
    }

    private func recognizedBlocks(
        sourceData: Data,
        sourceRect: CGRect
    ) async throws -> [ScreenshotOCRBlock] {
        if let cached = cachedOCR, cached.sourceRect == sourceRect {
            return cached.blocks
        }
        let service = ScreenshotTranslationService()
        let blocks = try await service.recognizeText(in: sourceData)
        cachedOCR = (sourceRect, blocks)
        return blocks
    }

    private func runTranslation(
        generation: Int,
        sourceData: Data,
        targetLanguage: ScreenshotTranslationLanguage
    ) async {
        do {
            let sourceRect = translationSourceRect ?? CGRect(origin: .zero, size: canvasSize)
            let ocrBlocks = try await recognizedBlocks(sourceData: sourceData, sourceRect: sourceRect)
            try Task.checkCancellation()
            guard translationGeneration == generation else { return }

            let plan = await ScreenshotTranslationService.classifyAsync(
                ocrBlocks,
                targetLanguage: targetLanguage
            )
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
        translationProgress = ScreenshotTranslationProgress(
            expectedIDs: Set(plan.groups.flatMap(\.blocks).map(\.id))
        )
        translationState = .translating(completed: 0, total: total)
        guard total > 0 else {
            translationState = .completed(count: 0)
            return
        }

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
                guard translationGeneration == generation else { return }
                updateTranslationProgress(generation: generation, total: total)
            } catch {
                if Task.isCancelled || Self.isCancellation(error) {
                    throw error
                }
                lastError = error
            }
        }

        guard translationGeneration == generation else { return }
        let progress = translationProgress
        if progress?.isComplete == true {
            translationState = .completed(count: progress?.successCount ?? 0)
        } else if let progress, progress.successCount > 0 {
            translationState = .partiallyCompleted(
                completed: progress.successCount,
                total: total
            )
        } else {
            throw lastError ?? ScreenshotTranslationError.noTextFound
        }
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
        guard translationGeneration == generation else { return }
        let blockID = response.clientIdentifier.flatMap(UUID.init(uuidString:))
        let translatedText = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard translationProgress?.recordResponse(
            blockID: blockID,
            translatedText: translatedText
        ) == true,
            let blockID
        else { return }

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
                confidence: sourceBlock.confidence,
                lineHeight: sourceBlock.lineHeight,
                sourceLines: sourceBlock.sourceLines
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

    private func updateTranslationProgress(generation: Int, total: Int) {
        guard translationGeneration == generation,
              let progress = translationProgress
        else { return }
        translationState = .translating(
            completed: min(progress.successCount, total),
            total: total
        )
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

    private func translationSourceData(for selection: CGRect?) -> Data? {
        guard let selection else { return originalData }
        let capture = ScreenshotCapture(
            data: originalData,
            screenFrame: CGRect(origin: .zero, size: canvasSize)
        )
        let outputRect = ScreenshotCoordinateSpace(
            screenFrame: CGRect(origin: .zero, size: canvasSize),
            canvasSize: canvasSize
        ).outputRect(fromCanvasRect: selection)
        do {
            return try ScreenshotService().crop(
                capture,
                to: outputRect,
                on: CGRect(origin: .zero, size: canvasSize)
            ).data
        } catch {
            // 改进 #10：以前 `try?` 吞掉裁剪失败的真实原因，翻译没反应时无从排查。
            JarvisLog.error(
                category: .storage,
                event: "translation.crop.failed",
                error: error
            )
            return nil
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
