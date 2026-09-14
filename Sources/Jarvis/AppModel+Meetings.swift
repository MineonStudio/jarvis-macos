import AVFoundation
import Foundation

extension AppModel {
    var meetingModelsReady: Bool {
        meetingModelState.isReady
    }

    func refreshMeetingModelState() {
        guard meetingModelPreparationTask == nil else { return }
        let availability = MeetingModelStorage.availability()
        meetingModelState = availability.isReady ? .ready : .notReady(availability)
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
        guard meetingModelsReady else {
            meetingProcessingState = .idle
            showToast("首次使用会议记录需要下载识别模型，请到设置中下载")
            return
        }
        if meetingCurrentRecordingID != nil {
            stopMeetingRecording()
        } else {
            Task { await startMeetingRecording() }
        }
    }

    func startMeetingRecording(language: MeetingLanguage = .simplifiedChinese) async {
        guard meetingCurrentRecordingID == nil else { return }

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
                showToast("已开始录音，正在同时保存麦克风和系统音频")
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
            finishStoppedMeeting(recordID: id, result: stopResult)
        }
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
            if let index = meetingRecords.firstIndex(where: { $0.id == id }) {
                var record = meetingRecords[index]
                record.duration = stopResult.duration
                record.status = .failed
                record.errorMessage = "录音已停止，原始录音已保留在本机"
                meetingRecords[index] = record
                persistMeeting(record)
            }
            meetingProcessingState = .failed("录音已停止，原始录音已保留在本机")
        }
    }

    func summarizeSelectedMeeting() {
        guard let selectedMeetingID,
              let record = meetingRecords.first(where: { $0.id == selectedMeetingID })
        else { return }
        summarizeMeeting(record, configuration: AIAPIConfiguration.load())
    }

    func deleteMeeting(_ record: MeetingRecord) {
        guard meetingCurrentRecordingID != record.id else { return }
        do {
            try meetingRepository.delete(record)
            meetingRecords.removeAll { $0.id == record.id }
            if selectedMeetingID == record.id {
                selectedMeetingID = meetingRecords.first?.id
            }
            meetingProcessingState = .idle
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

    func updateMeetingSpeakerName(recordID: UUID, speakerID: String, name: String) {
        guard let recordIndex = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let speakerIndex = meetingRecords[recordIndex].speakers.firstIndex(where: { $0.id == speakerID })
        else { return }
        meetingRecords[recordIndex].speakers[speakerIndex].name = trimmedName
        persistMeeting(meetingRecords[recordIndex])
    }

    private func processMeeting(_ record: MeetingRecord) {
        meetingProcessingTask?.cancel()
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let audioURL = try meetingRepository.audioURL(for: record)
                let microphoneURL = try meetingRepository.microphoneAudioURL(for: record)
                let systemAudioURL = try meetingRepository.systemAudioURL(for: record)
                try await MeetingAudioMixer.makeMixedAudio(
                    microphoneURL: microphoneURL,
                    systemAudioURL: systemAudioURL,
                    outputURL: audioURL
                )
                try await waitForMeetingAudioFile(at: audioURL)
                let transcription = try await meetingTranscriptionService.transcribe(
                    audioURL: audioURL,
                    language: record.language
                ) { [weak self] stage, progress in
                    Task { @MainActor [weak self] in
                        self?.meetingProcessingState = .processing(stage: stage, progress: progress)
                    }
                }

                guard let currentIndex = meetingRecords.firstIndex(where: { $0.id == record.id }) else { return }
                var updatedRecord = meetingRecords[currentIndex]
                updatedRecord.speakers = transcription.speakers
                updatedRecord.transcript = transcription.segments
                updatedRecord.status = .transcribed
                updatedRecord.errorMessage = nil
                meetingRecords[currentIndex] = updatedRecord
                persistMeeting(updatedRecord)

                let configuration = AIAPIConfiguration.load()
                guard configuration.isConfigured else {
                    meetingProcessingState = .awaitingConfiguration
                    showToast("逐字稿已保存，请先配置 AI 服务再生成总结")
                    return
                }
                summarizeMeeting(updatedRecord, configuration: configuration)
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func finishStoppedMeeting(
        recordID: UUID,
        result: MeetingRecordingStopResult
    ) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        var record = meetingRecords[index]
        record.duration = result.duration
        if result.systemAudioStarted,
           let systemAudioURL = try? meetingRepository.systemAudioURL(for: record),
           !isReadyAudioFile(at: systemAudioURL)
        {
            record.systemAudioFileName = nil
        }
        meetingRecords[index] = record
        persistMeeting(record)
        processMeeting(record)
    }

    private func summarizeMeeting(
        _ record: MeetingRecord,
        configuration: AIAPIConfiguration
    ) {
        guard !record.transcript.isEmpty else {
            meetingProcessingState = .failed("逐字稿为空，暂时无法生成总结")
            return
        }
        guard configuration.isConfigured else {
            meetingProcessingState = .awaitingConfiguration
            showToast("请先在设置中配置 AI 服务")
            return
        }

        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: 0.96)
        meetingProcessingTask?.cancel()
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Meeting summaries always use the shared API configuration from Settings.
                let summary = try await MeetingSummaryService(api: aiTextCompletionAPI).summarize(
                    record: record,
                    configuration: configuration
                )
                guard let index = meetingRecords.firstIndex(where: { $0.id == record.id }) else { return }
                meetingRecords[index].summary = summary
                meetingRecords[index].status = .ready
                meetingRecords[index].errorMessage = nil
                persistMeeting(meetingRecords[index])
                meetingProcessingState = .ready
                showToast("会议总结已生成")
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func updateMeetingFailure(recordID: UUID, message: String) {
        if let index = meetingRecords.firstIndex(where: { $0.id == recordID }) {
            meetingRecords[index].status = .failed
            meetingRecords[index].errorMessage = message
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .failed(message)
        showToast("会议处理失败：\(message)")
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
        guard FileManager.default.fileExists(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return false
        }
        return fileSize.intValue > 0
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

    private func updateMeetingMenuBarState() {
        JarvisMenuBarController.shared.updateMeetingRecordingState(
            isRecording: meetingCurrentRecordingID != nil,
            elapsed: meetingElapsed
        )
    }
}

private enum MeetingAudioFileError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "原始录音文件未完成保存，无法开始转写"
        }
    }
}
