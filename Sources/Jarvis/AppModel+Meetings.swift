import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    var meetingModelsReady: Bool {
        meetingModelState.isReady
    }

    func refreshMeetingModelState() {
        guard meetingModelPreparationTask == nil else { return }
        let availability = MeetingModelStorage.availability()
        meetingModelState = availability.isReady ? .ready : .notReady(availability)
        updateMeetingMenuBarState()
    }

    func prepareMeetingModels() {
        guard meetingModelPreparationTask == nil else { return }

        meetingModelState = .downloading(stage: .speakerDiarization, progress: 0.01)
        meetingModelPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await meetingTranscriptionService.prepareModels { [weak self] stage, progress in
                    Task { @MainActor [weak self] in
                        self?.meetingModelState = .downloading(stage: stage, progress: progress)
                    }
                }
                guard !Task.isCancelled else { return }
                meetingModelState = .ready
                updateMeetingMenuBarState()
            } catch is CancellationError {
                meetingModelPreparationTask = nil
                refreshMeetingModelState()
            } catch {
                meetingModelState = .failed(error.localizedDescription)
                meetingModelPreparationTask = nil
            }
            if meetingModelPreparationTask != nil {
                meetingModelPreparationTask = nil
            }
        }
    }

    func cancelMeetingModelPreparation() {
        meetingModelPreparationTask?.cancel()
        meetingModelPreparationTask = nil
        refreshMeetingModelState()
    }

    func toggleMeetingRecording() {
        guard meetingCurrentRecordingID != nil || requireAllPermissions() else { return }
        guard meetingModelsReady else {
            meetingProcessingState = .idle
            showToast("首次使用会议记录需要下载识别模型，请到设置中下载")
            return
        }
        if meetingCurrentRecordingID != nil {
            stopMeetingRecording()
        } else if !isStartingMeetingRecording {
            Task { await startMeetingRecording() }
        }
    }

    func startMeetingRecording(language: MeetingLanguage = .simplifiedChinese) async {
        guard meetingCurrentRecordingID == nil, !isStartingMeetingRecording else { return }
        isStartingMeetingRecording = true
        defer { isStartingMeetingRecording = false }

        guard meetingModelsReady else {
            meetingProcessingState = .idle
            showToast("首次使用会议记录需要下载识别模型，请到设置中下载")
            return
        }

        guard await microphoneAccessForMeeting() else {
            meetingProcessingState = .failed("请在系统设置中允许贾维斯访问麦克风")
            refreshPermissionStatus()
            return
        }

        let id = UUID()
        let now = Date()
        let title = MeetingRecord.defaultTitle
        let recordingURLs = meetingRepository.recordingURLs(for: id)
        let recordingsUsage = meetingRepository.recordingsUsageBytes()
        if recordingsUsage >= MeetingRepository.recordingsWarningBytes {
            let gigabytes = Double(recordingsUsage) / (1024 * 1024 * 1024)
            showToast(String(format: "会议录音已占用约 %.1f GB，可删除旧会议释放空间", gigabytes))
        }

        do {
            let sources = try await meetingRecorder.start(
                microphoneURL: recordingURLs.microphone,
                systemAudioURL: recordingURLs.system
            )
            let record = MeetingRecord(
                id: id,
                title: title,
                createdAt: now,
                audioFileName: recordingURLs.mixed.lastPathComponent,
                microphoneAudioFileName: recordingURLs.microphone.lastPathComponent,
                systemAudioFileName: sources.systemAudioStarted
                    ? recordingURLs.system.lastPathComponent
                    : nil,
                language: language
            )
            try meetingRepository.save(record)
            meetingRecords.removeAll { $0.id == id }
            meetingRecords.insert(record, at: 0)
            meetingCurrentRecordingID = id
            selectedMeetingID = id
            meetingElapsed = 0
            updateMeetingMenuBarState()
            meetingProcessingState = .recording
            meetingRecordingTimer?.cancel()
            meetingRecordingTimer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.meetingCurrentRecordingID == id else { return }
                    self.meetingElapsed = self.meetingRecorder.isRecording
                        ? Date().timeIntervalSince(now)
                        : self.meetingElapsed
                    self.updateMeetingMenuBarState()
                }
            }
            if let systemAudioErrorMessage = sources.systemAudioErrorMessage {
                showToast("已开始录音；系统音频未采集：\(systemAudioErrorMessage)")
            } else {
                showToast("已开始录音")
            }
        } catch {
            await meetingRecorder.cancel()
            meetingProcessingState = .failed("开始录音失败：\(error.localizedDescription)")
        }
    }

    func stopMeetingRecording() {
        guard let id = meetingCurrentRecordingID,
              let index = meetingRecords.firstIndex(where: { $0.id == id })
        else { return }

        let duration = meetingElapsed
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingElapsed = duration
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()

        var record = meetingRecords[index]
        record.duration = max(duration, 0)
        record.status = .transcribing
        meetingRecords[index] = record
        persistMeeting(record)
        meetingProcessingState = .processing(stage: .diarizing, progress: 0)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stopResult = await meetingRecorder.stop()
            finishStoppedMeeting(recordID: id, result: stopResult, processAfterStop: true)
        }
    }

    func handleUnexpectedMeetingStop() {
        guard meetingCurrentRecordingID != nil else { return }
        showToast("录音因输入设备中断而结束，将处理已写入的音频")
        stopMeetingRecording()
    }

    func cancelMeetingRecording() {
        guard let id = meetingCurrentRecordingID else { return }
        let duration = meetingElapsed
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()
        meetingElapsed = duration
        selectedMeetingID = id
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stopResult = await meetingRecorder.stop()
            finishStoppedMeeting(
                recordID: id,
                result: stopResult,
                processAfterStop: false,
                failureMessage: "录音已停止，原始录音已保留在本机，可重新处理"
            )
        }
    }

    func finalizeMeetingRecordingForTermination() async {
        guard let id = meetingCurrentRecordingID else { return }
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()
        let stopResult = await meetingRecorder.stop()
        finishStoppedMeeting(
            recordID: id,
            result: stopResult,
            processAfterStop: false,
            failureMessage: "应用退出时已保存录音，可重新处理"
        )
    }

    func summarizeSelectedMeeting() {
        guard let selectedMeetingID,
              let record = meetingRecords.first(where: { $0.id == selectedMeetingID })
        else { return }
        ensureMeetingDetailLoaded(record.id)
        enqueueMeetingProcessing(recordID: record.id, kind: .summarizeOnly)
    }

    func retryMeetingProcessing(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        let current = meetingRecords.first { $0.id == record.id } ?? record
        if current.transcript.isEmpty {
            enqueueMeetingProcessing(recordID: current.id, kind: .transcribeAndSummarize)
        } else {
            enqueueMeetingProcessing(recordID: current.id, kind: .summarizeOnly)
        }
    }

    func ensureMeetingDetailLoaded(_ id: UUID) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == id }) else { return }
        if !meetingRecords[index].detail.isEmpty {
            return
        }
        guard let detail = meetingRepository.loadDetail(for: id), !detail.isEmpty else { return }
        meetingRecords[index].applyDetail(detail)
    }

    func copyMeetingMarkdown(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }) else { return }
        guard !current.transcript.isEmpty || current.summary != nil else {
            showToast("还没有可复制的会议内容")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current.markdownDocument(), forType: .string)
        showToast("会议纪要已复制")
    }

    func exportMeetingMarkdown(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }) else { return }
        guard !current.transcript.isEmpty || current.summary != nil else {
            showToast("还没有可导出的会议内容")
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(current.title).md"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try current.markdownDocument().write(to: url, atomically: true, encoding: .utf8)
                self?.showToast("会议纪要已导出")
            } catch {
                self?.showToast("导出失败：\(error.localizedDescription)")
            }
        }
    }

    func deleteMeeting(_ record: MeetingRecord) {
        guard meetingCurrentRecordingID != record.id else {
            showToast("请先结束当前录音，再删除这条会议")
            return
        }
        meetingProcessingQueue.removeAll { $0.recordID == record.id }
        let wasActive = meetingActiveProcessingID == record.id
        if wasActive {
            meetingProcessingTask?.cancel()
        }
        do {
            try meetingRepository.delete(record)
            meetingRecords.removeAll { $0.id == record.id }
            if selectedMeetingID == record.id {
                selectedMeetingID = meetingRecords.first?.id
            }
            if !wasActive, meetingActiveProcessingID == nil {
                meetingProcessingState = .idle
            }
        } catch {
            showToast("删除会议失败：\(error.localizedDescription)")
        }
    }

    func meetingAudioURL(for record: MeetingRecord) -> URL? {
        try? meetingRepository.audioURL(for: record)
    }

    func meetingMicrophoneAudioURL(for record: MeetingRecord) -> URL? {
        try? meetingRepository.microphoneAudioURL(for: record)
    }

    func meetingSystemAudioURL(for record: MeetingRecord) -> URL? {
        try? meetingRepository.systemAudioURL(for: record)
    }

    func updateMeetingTitle(recordID: UUID, title: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingRecords[index].title = normalizedTitle.isEmpty ? MeetingRecord.defaultTitle : normalizedTitle
        persistMeeting(meetingRecords[index])
    }

    private func enqueueMeetingProcessing(recordID: UUID, kind: MeetingProcessingJob.Kind) {
        if meetingActiveProcessingID == recordID {
            return
        }
        let job = MeetingProcessingJob(recordID: recordID, kind: kind)
        if !meetingProcessingQueue.contains(job) {
            meetingProcessingQueue.append(job)
        }
        startNextMeetingProcessingIfNeeded()
    }

    private func startNextMeetingProcessingIfNeeded() {
        guard meetingActiveProcessingID == nil else { return }
        guard meetingProcessingQueue.isEmpty == false else {
            Task { await meetingTranscriptionService.releaseCachedModels() }
            return
        }

        let job = meetingProcessingQueue.removeFirst()
        guard let record = meetingRecords.first(where: { $0.id == job.recordID }) else {
            startNextMeetingProcessingIfNeeded()
            return
        }

        switch job.kind {
        case .transcribeAndSummarize:
            processMeeting(record)
        case .summarizeOnly:
            startSummarizeTask(record)
        }
    }

    private func processMeeting(_ record: MeetingRecord) {
        meetingActiveProcessingID = record.id
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .transcribing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .diarizing, progress: 0)
        lastMeetingProgressStage = .diarizing
        lastMeetingProgressValue = 0
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { completeActiveMeetingProcessing(for: record.id) }
            do {
                let prepared = try await prepareAudioForTranscription(record)
                try await waitForMeetingAudioFile(at: prepared.mixedURL)
                let transcription = try await meetingTranscriptionService.transcribe(
                    audioURL: prepared.mixedURL,
                    language: record.language
                ) { [weak self] stage, progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.meetingActiveProcessingID == record.id else { return }
                        let shouldPublish = self.lastMeetingProgressStage != stage
                            || abs(progress - self.lastMeetingProgressValue) >= 0.01
                            || progress >= 1
                        guard shouldPublish else { return }
                        self.lastMeetingProgressStage = stage
                        self.lastMeetingProgressValue = progress
                        self.meetingProcessingState = .processing(stage: stage, progress: progress)
                    }
                }

                guard let currentIndex = meetingRecords.firstIndex(where: { $0.id == record.id }) else { return }
                var updatedRecord = meetingRecords[currentIndex]
                updatedRecord.speakers = transcription.speakers
                updatedRecord.transcript = transcription.segments
                updatedRecord.systemAudioFileName = prepared.systemAudioFileName
                updatedRecord.errorMessage = nil
                if transcription.segments.isEmpty {
                    updatedRecord.status = .failed
                    updatedRecord.errorMessage = "未识别到有效语音，请检查音量后重新处理"
                    meetingRecords[currentIndex] = updatedRecord
                    persistMeeting(updatedRecord)
                    meetingProcessingState = .failed(updatedRecord.errorMessage ?? "")
                    showToast("会议处理失败：\(updatedRecord.errorMessage ?? "")")
                    return
                }

                updatedRecord.status = .transcribed
                meetingRecords[currentIndex] = updatedRecord
                persistMeeting(updatedRecord)

                let configuration = AIAPIConfiguration.load()
                guard configuration.isConfigured else {
                    meetingProcessingState = .awaitingConfiguration
                    showToast("逐字稿已保存，请先配置 AI 服务再生成总结")
                    return
                }
                try await performSummarize(updatedRecord, configuration: configuration)
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func startSummarizeTask(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        let record = meetingRecords.first { $0.id == record.id } ?? record
        let configuration = AIAPIConfiguration.load()
        guard !record.transcript.isEmpty else {
            meetingProcessingState = .failed("逐字稿为空，暂时无法生成总结")
            startNextMeetingProcessingIfNeeded()
            return
        }
        guard configuration.isConfigured else {
            meetingProcessingState = .awaitingConfiguration
            showToast("请先在设置中配置 AI 服务")
            startNextMeetingProcessingIfNeeded()
            return
        }

        meetingActiveProcessingID = record.id
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: 0.96)
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { completeActiveMeetingProcessing(for: record.id) }
            do {
                try await performSummarize(record, configuration: configuration)
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func performSummarize(
        _ record: MeetingRecord,
        configuration: AIAPIConfiguration
    ) async throws {
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: 0.96)
        let operationID = JarvisLog.operationID()
        JarvisLog.notice(
            category: .meeting,
            event: "summary.begin",
            operationID: operationID,
            fields: [
                "meetingID": record.id.uuidString,
                "transcriptSegments": String(record.transcript.count),
                "resuming": record.summaryCheckpoint == nil ? "false" : "true"
            ]
        )
        let summary = try await MeetingSummaryService(api: aiTextCompletionAPI).summarize(
            record: record,
            configuration: configuration,
            checkpoint: record.summaryCheckpoint,
            onCheckpoint: { [weak self] checkpoint in
                guard let self,
                      let index = self.meetingRecords.firstIndex(where: { $0.id == record.id })
                else { return }
                self.meetingRecords[index].summaryCheckpoint = checkpoint
                self.persistMeeting(self.meetingRecords[index])
                JarvisLog.info(
                    category: .meeting,
                    event: "summary.checkpoint",
                    operationID: operationID,
                    fields: [
                        "meetingID": record.id.uuidString,
                        "stage": checkpoint.stage.rawValue,
                        "completedChunks": String(checkpoint.completedChunkCount),
                        "totalChunks": String(checkpoint.totalChunkCount),
                        "factCount": String(checkpoint.facts.count)
                    ]
                )
            }
        )
        guard let index = meetingRecords.firstIndex(where: { $0.id == record.id }) else { return }
        meetingRecords[index].summary = summary
        meetingRecords[index].status = .ready
        meetingRecords[index].summaryCheckpoint = nil
        meetingRecords[index].errorMessage = nil
        persistMeeting(meetingRecords[index])
        JarvisLog.notice(
            category: .meeting,
            event: "summary.complete",
            operationID: operationID,
            result: "success",
            fields: [
                "meetingID": record.id.uuidString,
                "keyPoints": String(summary.keyPoints.count),
                "decisions": String(summary.decisions.count),
                "actionItems": String(summary.actionItems.count),
                "openQuestions": String(summary.openQuestions.count)
            ]
        )
        meetingProcessingState = .ready
        showToast("会议总结已生成")
    }

    private func completeActiveMeetingProcessing(for recordID: UUID) {
        guard meetingActiveProcessingID == recordID else { return }
        meetingActiveProcessingID = nil
        meetingProcessingTask = nil
        startNextMeetingProcessingIfNeeded()
    }

    private func prepareAudioForTranscription(
        _ record: MeetingRecord
    ) async throws -> (mixedURL: URL, systemAudioFileName: String?) {
        let audioURL = try meetingRepository.audioURL(for: record)
        let microphoneURL = try meetingRepository.microphoneAudioURL(for: record)
        var systemAudioURL = try meetingRepository.systemAudioURL(for: record)
        var systemAudioFileName = record.systemAudioFileName
        let recordingURLs = meetingRepository.recordingURLs(for: record.id)

        if let currentSystemURL = systemAudioURL,
           currentSystemURL.pathExtension.lowercased() == "caf",
           MeetingAudioMixer.isReadyAudioFile(at: currentSystemURL)
        {
            do {
                try await MeetingAudioMixer.transcodeToM4A(
                    inputURL: currentSystemURL,
                    outputURL: recordingURLs.systemCompressed
                )
                MeetingAudioMixer.removeFileIfExists(at: currentSystemURL)
                systemAudioURL = recordingURLs.systemCompressed
                systemAudioFileName = recordingURLs.systemCompressed.lastPathComponent
            } catch {
                try await MeetingAudioMixer.makeMixedAudio(
                    microphoneURL: microphoneURL,
                    systemAudioURL: currentSystemURL,
                    outputURL: audioURL,
                    systemAudioDelay: record.resolvedSystemAudioStartOffset
                )
                MeetingAudioMixer.removeFileIfExists(at: currentSystemURL)
                return (audioURL, nil)
            }
        }

        try await MeetingAudioMixer.makeMixedAudio(
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            outputURL: audioURL,
            systemAudioDelay: record.resolvedSystemAudioStartOffset
        )
        MeetingAudioMixer.removeFileIfExists(at: recordingURLs.system)
        return (audioURL, systemAudioFileName)
    }

    private func finishStoppedMeeting(
        recordID: UUID,
        result: MeetingRecordingStopResult,
        processAfterStop: Bool,
        failureMessage: String? = nil
    ) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        var record = meetingRecords[index]
        record.duration = result.duration
        record.systemAudioStartOffset = result.systemAudioStartOffset
        if result.systemAudioStarted,
           let systemAudioURL = try? meetingRepository.systemAudioURL(for: record),
           !isReadyAudioFile(at: systemAudioURL)
        {
            record.systemAudioFileName = nil
        }
        if let failureMessage {
            record.status = .failed
            record.errorMessage = failureMessage
            meetingRecords[index] = record
            persistMeeting(record)
            meetingProcessingState = .failed(failureMessage)
            return
        }
        meetingRecords[index] = record
        persistMeeting(record)
        if let systemError = result.systemAudioErrorMessage, result.systemAudioStarted {
            showToast(systemError)
        }
        if processAfterStop {
            enqueueMeetingProcessing(recordID: record.id, kind: .transcribeAndSummarize)
        }
    }

    private func updateMeetingFailure(recordID: UUID, message: String) {
        var hasTranscript = false
        if let index = meetingRecords.firstIndex(where: { $0.id == recordID }) {
            hasTranscript = !meetingRecords[index].transcript.isEmpty
            meetingRecords[index].status = hasTranscript ? .summaryFailed : .failed
            meetingRecords[index].errorMessage = message
            if var checkpoint = meetingRecords[index].summaryCheckpoint {
                checkpoint.stage = .failed
                checkpoint.errorMessage = message
                checkpoint.updatedAt = Date()
                meetingRecords[index].summaryCheckpoint = checkpoint
            }
            persistMeeting(meetingRecords[index])
            let failureEvent = hasTranscript ? "summary.failed" : "processing.failed"
            JarvisLog.error(
                category: .meeting,
                event: failureEvent,
                fields: [
                    "meetingID": recordID.uuidString,
                    "hasTranscript": hasTranscript ? "true" : "false"
                ]
            )
        }
        meetingProcessingState = .failed(message)
        showToast(
            hasTranscript
                ? "会议纪要生成失败：\(message)"
                : "会议处理失败：\(message)"
        )
    }

    private func persistMeeting(_ record: MeetingRecord) {
        do {
            try meetingRepository.save(record)
        } catch {
            showToast("保存会议记录失败：\(error.localizedDescription)")
        }
    }

    private func waitForMeetingAudioFile(at url: URL) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !isReadyAudioFile(at: url) {
            guard !Task.isCancelled else { throw CancellationError() }
            guard Date() < deadline else {
                throw MeetingAudioFileError.unavailable
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func isReadyAudioFile(at url: URL) -> Bool {
        MeetingAudioMixer.isReadyAudioFile(at: url)
    }

    private func microphoneAccessForMeeting() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            JarvisPrivacyPermissionAccess.openSettings(for: .microphone)
            return false
        @unknown default:
            return false
        }
    }

    func updateMeetingMenuBarState() {
        JarvisMenuBarController.shared.updateMeetingRecordingState(
            isRecording: meetingCurrentRecordingID != nil,
            elapsed: meetingElapsed,
            modelsReady: meetingModelsReady
        )
    }
}

struct MeetingProcessingJob: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case transcribeAndSummarize
        case summarizeOnly
    }

    let recordID: UUID
    let kind: Kind
}

private enum MeetingAudioFileError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "原始录音文件未完成保存，无法开始转写"
        }
    }
}
