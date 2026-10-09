import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

extension AppModel {
    var meetingModelsReady: Bool {
        meetingModelState.isReady
    }

    func refreshMeetingModelState() {
        guard meetingModelPreparationTask == nil,
              meetingModelAvailabilityTask == nil
        else { return }
        meetingModelAvailabilityTask = Task { @MainActor [weak self] in
            let stored = await Task.detached(priority: .utility) {
                MeetingModelStorage.availability()
            }.value
            let speechReady = await MeetingSpeechAssets.isInstalled()
            let availability = MeetingModelAvailability(
                speakerDiarizationReady: stored.speakerDiarizationReady,
                chineseTranscriptionReady: speechReady
            )
            guard let self,
                  !Task.isCancelled,
                  meetingModelPreparationTask == nil
            else { return }
            meetingModelAvailabilityTask = nil
            meetingModelAvailability = availability
            meetingModelState = availability.isReady ? .ready : .notReady(availability)
            updateMeetingMenuBarState()
        }
    }

    func prepareMeetingModels() {
        startMeetingModelPreparation(for: MeetingModelPreparationStage.allCases)
    }

    func prepareMeetingModel(_ stage: MeetingModelPreparationStage) {
        startMeetingModelPreparation(for: [stage])
    }

    private func startMeetingModelPreparation(for stages: [MeetingModelPreparationStage]) {
        guard canManageMeetingModels else { return }

        meetingModelAvailabilityTask?.cancel()
        meetingModelAvailabilityTask = nil
        meetingModelPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for stage in stages {
                guard !Task.isCancelled else { break }
                meetingModelState = .downloading(stage: stage, progress: 0.01)
                do {
                    try await meetingTranscriptionService.prepareModel(stage) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self,
                                  case let .downloading(activeStage, _) = meetingModelState,
                                  activeStage == stage
                            else {
                                return
                            }
                            meetingModelState = .downloading(stage: stage, progress: progress)
                            let bytes = MeetingSpeechDownloadMeter.snapshot()
                            meetingModelDownloadCompletedBytes = bytes.completed
                            meetingModelDownloadTotalBytes = bytes.total
                        }
                    }
                    guard !Task.isCancelled else { break }
                } catch is CancellationError {
                    break
                } catch {
                    meetingModelPreparationTask = nil
                    meetingModelState = .failed(
                        stage: stage,
                        operation: .download,
                        message: error.localizedDescription
                    )
                    return
                }
            }

            meetingModelPreparationTask = nil
            meetingModelState = .checking
            refreshMeetingModelState()
        }
    }

    func removeMeetingModel(_ stage: MeetingModelPreparationStage) {
        guard canManageMeetingModels else { return }

        meetingModelState = .removing(stage)
        meetingModelPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await meetingTranscriptionService.removeModel(stage)
                meetingModelPreparationTask = nil
                meetingModelState = .checking
                refreshMeetingModelState()
            } catch {
                meetingModelPreparationTask = nil
                meetingModelState = .failed(
                    stage: stage,
                    operation: .remove,
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancelMeetingModelPreparation() {
        guard case .downloading = meetingModelState else { return }
        meetingModelPreparationTask?.cancel()
        meetingModelState = .checking
        refreshMeetingModelState()
    }

    func toggleMeetingRecording() {
        if meetingCurrentRecordingID == nil {
            refreshPermissionStatus()
            guard microphonePermissionGranted else {
                promptForTaskPermission(.microphone)
                return
            }
        }
        guard meetingModelsReady else {
            meetingProcessingState = .idle
            if case .checking = meetingModelState {
                showToast("正在检查会议识别模型，请稍后再试")
            } else {
                showToast(JarvisFeedbackCopy.downloadModelsFirst)
            }
            return
        }
        if meetingCurrentRecordingID != nil {
            stopMeetingRecording()
        } else if !isStartingMeetingRecording {
            Task { await startMeetingRecording() }
        }
    }

    func startMeetingRecording(
        language: MeetingLanguage = .simplifiedChinese,
        reusing recordID: UUID? = nil
    ) async {
        guard meetingCurrentRecordingID == nil, !isStartingMeetingRecording else { return }
        guard !meetingRecorder.isStopping else {
            showToast(JarvisFeedbackCopy.meetingStopInProgress)
            return
        }
        isStartingMeetingRecording = true
        defer { isStartingMeetingRecording = false }

        guard meetingModelsReady else {
            meetingProcessingState = .idle
            showToast(JarvisFeedbackCopy.downloadModelsFirst)
            return
        }

        guard await microphoneAccessForMeeting() else {
            meetingProcessingState = .failed("缺少麦克风权限。请到系统设置 > 隐私与安全性 > 麦克风，允许贾维斯。")
            refreshPermissionStatus()
            showToast(JarvisFeedbackCopy.microphoneRequired)
            return
        }

        let reused = reusableMeetingPlaceholder(recordID: recordID)
        let id = reused?.id ?? UUID()
        let now = reused?.createdAt ?? Date()
        let title = reused?.title ?? MeetingRecord.defaultTitle
        let recordingURLs = meetingRepository.recordingURLs(for: id)
        let recordingsUsage = meetingRepository.recordingsUsageBytes()
        if recordingsUsage >= MeetingRepository.recordingsWarningBytes {
            let gigabytes = Double(recordingsUsage) / (1024 * 1024 * 1024)
            showToast(JarvisFeedbackCopy.recordingsUsageWarning(gigabytes))
        }
        warnIfMeetingDiskIsLow()

        let capturesSystemAudio = meetingCaptureMode == .dual
        do {
            let sources = try await meetingRecorder.start(
                meetingID: id,
                microphoneURL: recordingURLs.microphone,
                systemAudioURL: recordingURLs.system,
                capturesSystemAudio: capturesSystemAudio
            )
            let captureMode: MeetingCaptureMode = capturesSystemAudio && sources.systemAudioStarted
                ? .dual
                : .microphone
            if let reusedIndex = meetingRecords.firstIndex(where: { $0.id == id }), reused != nil {
                var record = meetingRecords[reusedIndex]
                record.duration = 0
                record.microphoneAudioFileName = recordingURLs.microphone.lastPathComponent
                record.systemAudioFileName = sources.systemAudioStarted
                    ? recordingURLs.system.lastPathComponent
                    : nil
                record.language = language
                record.captureMode = captureMode
                record.status = .recording
                record.errorMessage = nil
                record.interruptedRecording = nil
                record.awaitingAssets = false
                record.audioChunks = []
                try meetingRepository.save(record)
                meetingRecords[reusedIndex] = record
            } else {
                let record = MeetingRecord(
                    id: id,
                    title: title,
                    createdAt: now,
                    audioFileName: recordingURLs.mixed.lastPathComponent,
                    microphoneAudioFileName: recordingURLs.microphone.lastPathComponent,
                    systemAudioFileName: sources.systemAudioStarted
                        ? recordingURLs.system.lastPathComponent
                        : nil,
                    language: language,
                    captureMode: captureMode,
                    awaitingAssets: false
                )
                try meetingRepository.save(record)
                meetingRecords.removeAll { $0.id == id }
                meetingRecords.insert(record, at: 0)
            }
            meetingCurrentRecordingID = id
            selectedMeetingID = id
            meetingElapsed = 0
            meetingElapsedOrigin = Date()
            meetingElapsedAccumulated = 0
            meetingRecoverySnapshotBucket = -1
            meetingMicrophoneSilentSince = nil
            meetingDidWarnAboutSilence = false
            meetingSystemSilentSince = nil
            meetingDidWarnAboutSystemSilence = false
            meetingRecordingPaused = false
            updateMeetingMenuBarState()
            meetingProcessingState = .recording
            meetingRecordingTimer?.cancel()
            meetingRecordingTimer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self, self.meetingCurrentRecordingID == id else { return }
                    if !self.meetingRecordingPaused {
                        self.meetingElapsed = self.meetingElapsedAccumulated
                            + Date().timeIntervalSince(self.meetingElapsedOrigin)
                    }
                    let closed = self.meetingRecorder.rotateIfDue()
                    if !closed.isEmpty {
                        self.appendMeetingChunks(closed, recordID: id)
                    }
                    self.snapshotRecordingIfNeeded(id)
                    self.refreshMeetingRecordingMeters()
                    self.warnIfMicrophoneStaysSilent()
                    self.warnIfSystemAudioStaysSilent()
                    self.updateMeetingMenuBarState()
                }
            }
            if sources.systemAudioErrorMessage != nil {
                showToast(JarvisFeedbackCopy.recordingStartedWithoutSystemAudio)
            } else {
                showToast(JarvisFeedbackCopy.recordingStarted)
            }
        } catch {
            await meetingRecorder.discard()
            meetingProcessingState = .failed("开始录音失败：\(error.localizedDescription)")
            showToast(JarvisFeedbackCopy.recordingStartFailed)
        }
    }

    func stopMeetingRecording() {
        guard let id = meetingCurrentRecordingID,
              let index = meetingRecords.firstIndex(where: { $0.id == id })
        else { return }

        let duration = meetingElapsed
        meetingRecordingTimer?.cancel()
        meetingRecordingTimer = nil
        meetingRecordingPaused = false
        meetingElapsed = duration
        meetingCurrentRecordingID = nil
        updateMeetingMenuBarState()

        var record = meetingRecords[index]
        record.duration = max(duration, 0)
        record.audioChunks = meetingRecorder.snapshotChunks()
        record.status = .transcribing
        meetingRecords[index] = record
        persistMeeting(record)
        meetingProcessingState = .processing(stage: .diarizing, progress: 0)
        // 同步立 flag：下面的 Task 是异步调度的，不立的话用户可立即开始新会话，
        // 旧 stop 恢复后会清掉新会话的采集状态（S-3）。
        meetingRecorder.markStopInFlight()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let stopResult = await meetingRecorder.stop()
            finishStoppedMeeting(recordID: id, result: stopResult, processAfterStop: true)
        }
    }

    func handleUnexpectedMeetingStop() {
        guard meetingCurrentRecordingID != nil else { return }
        showToast(JarvisFeedbackCopy.recordingInterrupted)
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
        // 同上：同步立 flag，关掉 Task 调度窗口（S-3）。
        meetingRecorder.markStopInFlight()
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
              meetingRecords.contains(where: { $0.id == selectedMeetingID })
        else { return }
        summarizeMeeting(recordID: selectedMeetingID)
    }

    func summarizeMeeting(recordID: UUID, preserveUserEdits: Bool = true) {
        guard meetingRecords.contains(where: { $0.id == recordID }) else { return }
        ensureMeetingDetailLoaded(recordID)
        guard MeetingTranscriptConsent.isConfirmed else {
            meetingPreserveUserEdits = preserveUserEdits
            meetingTranscriptConsentRecordID = recordID
            return
        }
        if !preserveUserEdits, let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
           let summary = meetingRecords[index].summary
        {
            meetingRecords[index].minutesVersions.append(MeetingMinutesVersion(summary: summary))
            meetingRecords[index].summaryCheckpoint = nil
            persistMeeting(meetingRecords[index])
        }
        meetingPreserveUserEdits = preserveUserEdits
        enqueueMeetingProcessing(
            recordID: recordID,
            kind: .summarizeOnly,
            preserveUserEdits: preserveUserEdits
        )
    }

    func confirmMeetingTranscriptConsent() {
        MeetingTranscriptConsent.confirm()
        let recordID = meetingTranscriptConsentRecordID
        meetingTranscriptConsentRecordID = nil
        if let recordID {
            summarizeMeeting(recordID: recordID, preserveUserEdits: meetingPreserveUserEdits)
        }
    }

    func cancelMeetingTranscriptConsent() {
        meetingTranscriptConsentRecordID = nil
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

    func matchingMeetingIDs(searchText: String) async -> Set<UUID> {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Set(meetingRecords.map(\.id)) }
        let records = meetingRecords
        let repository = meetingRepository
        return await Task.detached(priority: .userInitiated) {
            Set(records.compactMap { record in
                record.matchesSearch(query)
                    || repository.detailMatchesSearch(for: record.id, query: query)
                    ? record.id
                    : nil
            })
        }.value
    }

    func copyMeetingMarkdown(_ record: MeetingRecord, includeTranscript: Bool = false) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }) else { return }
        guard current.summary != nil || (includeTranscript && !current.transcript.isEmpty) else {
            showToast(JarvisFeedbackCopy.nothingToCopy)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            current.markdownDocument(includeTranscript: includeTranscript),
            forType: .string
        )
        showToast(JarvisFeedbackCopy.copied)
    }

    func exportMeetingPlainTranscript(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }),
              !current.transcript.isEmpty
        else {
            showToast(JarvisFeedbackCopy.nothingToExport)
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(current.title)-逐字稿.txt"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try current.plainTranscriptDocument().write(to: url, atomically: true, encoding: .utf8)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch {
                self?.showToast(JarvisFeedbackCopy.exportFailed)
            }
        }
    }

    func exportMeetingPDF(_ record: MeetingRecord) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }),
              current.summary != nil || !current.transcript.isEmpty
        else {
            showToast(JarvisFeedbackCopy.nothingToExport)
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(current.title).pdf"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try MeetingExport.pdfData(for: current).write(to: url)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch {
                self?.showToast(JarvisFeedbackCopy.exportFailed)
            }
        }
    }

    func exportMeetingMarkdown(_ record: MeetingRecord, includeTranscript: Bool = false) {
        ensureMeetingDetailLoaded(record.id)
        guard let current = meetingRecords.first(where: { $0.id == record.id }) else { return }
        guard current.summary != nil || (includeTranscript && !current.transcript.isEmpty) else {
            showToast(JarvisFeedbackCopy.nothingToExport)
            return
        }
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = includeTranscript
            ? "\(current.title)-完整记录.md"
            : "\(current.title).md"
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try current.markdownDocument(includeTranscript: includeTranscript)
                    .write(to: url, atomically: true, encoding: .utf8)
                self?.showToast(JarvisFeedbackCopy.exported)
            } catch {
                self?.showToast(JarvisFeedbackCopy.exportFailed)
            }
        }
    }

    func deleteMeeting(_ record: MeetingRecord) {
        guard meetingCurrentRecordingID != record.id else {
            showToast(JarvisFeedbackCopy.finishRecordingFirst)
            return
        }
        meetingProcessingQueue.removeAll { $0.recordID == record.id }
        let wasActive = meetingActiveProcessingID == record.id
        if wasActive {
            // #14：先取消任务，再同步清掉 active 标记。被取消任务的 defer
            // （completeActiveMeetingProcessing）稍后才跑，会因 guard 直接 no-op，
            // 不会把我们下面推进的状态覆盖掉。
            meetingProcessingTask?.cancel()
            meetingProcessingTask = nil
            meetingActiveProcessingID = nil
        }
        // #14：删的是正在处理的会议时，队列里有排队就起下一个，空了就回 .idle——
        // 以前这里只在 !wasActive 时回 idle，删正在处理的会议会让状态永远卡在 .processing。
        defer {
            if wasActive {
                startNextMeetingProcessingIfNeeded()
            }
            if meetingActiveProcessingID == nil {
                meetingProcessingState = .idle
            }
        }
        do {
            try meetingRepository.delete(record)
            meetingRecords.removeAll { $0.id == record.id }
            if selectedMeetingID == record.id {
                selectedMeetingID = meetingRecords.first?.id
            }
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "meeting.delete.failed",
                error: error,
                fields: ["meetingID": record.id.uuidString]
            )
            showToast(JarvisFeedbackCopy.deleteFailed)
        }
    }

    func meetingAudioURL(for record: MeetingRecord) -> URL? {
        try? meetingRepository.audioURL(for: record)
    }

    func meetingMicrophoneAudioURL(for record: MeetingRecord) -> URL? {
        try? meetingRepository.microphoneAudioURL(for: record)
    }

    func updateMeetingTitle(recordID: UUID, title: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        meetingRecords[index].title = normalizedTitle.isEmpty ? MeetingRecord.defaultTitle : normalizedTitle
        persistMeeting(meetingRecords[index])
    }

    func setMeetingActionItemCompleted(
        recordID: UUID,
        actionItemID: UUID,
        isCompleted: Bool
    ) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary,
              let itemIndex = summary.actionItems.firstIndex(where: { $0.id == actionItemID })
        else { return }
        summary.actionItems[itemIndex].isCompleted = isCompleted
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func updateMeetingOverview(recordID: UUID, overview: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary
        else { return }
        summary.overview = overview
        summary.overviewIsUserEdited = true
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func updateMeetingPoint(recordID: UUID, pointID: String, title: String, detail: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary,
              let pointIndex = summary.points.firstIndex(where: { $0.id == pointID })
        else { return }
        summary.points[pointIndex].title = title
        summary.points[pointIndex].detail = detail
        summary.points[pointIndex].isUserEdited = true
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func updateMeetingActionItemText(recordID: UUID, actionItemID: UUID, task: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              var summary = meetingRecords[index].summary,
              let itemIndex = summary.actionItems.firstIndex(where: { $0.id == actionItemID })
        else { return }
        summary.actionItems[itemIndex].task = task
        summary.actionItems[itemIndex].isUserEdited = true
        meetingRecords[index].summary = summary
        persistMeeting(meetingRecords[index])
    }

    func renameMeetingSpeaker(recordID: UUID, speakerID: String, name: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let speakerIndex = meetingRecords[index].speakers.firstIndex(where: { $0.id == speakerID })
        else { return }
        let oldName = meetingRecords[index].speakers[speakerIndex].name
        guard oldName != trimmed else { return }
        meetingRecords[index].speakers[speakerIndex].name = trimmed
        if var summary = meetingRecords[index].summary {
            for itemIndex in summary.actionItems.indices where summary.actionItems[itemIndex].owner == oldName {
                summary.actionItems[itemIndex].owner = trimmed
            }
            meetingRecords[index].summary = summary
        }
        persistMeeting(meetingRecords[index])
    }

    func reassignMeetingSegment(recordID: UUID, segmentID: UUID, speakerID: String) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              let segmentIndex = meetingRecords[index].transcript.firstIndex(where: { $0.id == segmentID }),
              meetingRecords[index].speakers.contains(where: { $0.id == speakerID })
        else { return }
        meetingRecords[index].transcript[segmentIndex].speakerID = speakerID
        meetingRecords[index].transcript[segmentIndex].isUncertainSpeaker =
            speakerID == MeetingMinutesAlgorithm.uncertainSpeakerID
        meetingRecords[index].segmentSpeakerOverrides.removeAll { $0.segmentID == segmentID }
        meetingRecords[index].segmentSpeakerOverrides.append(
            MeetingSegmentSpeakerOverride(segmentID: segmentID, speakerID: speakerID)
        )
        persistMeeting(meetingRecords[index])
    }

    func remergeMeetingSpeakers(recordID: UUID) {
        ensureMeetingDetailLoaded(recordID)
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        let merged = MeetingSpeakerRemerge.apply(
            segments: meetingRecords[index].transcript,
            turns: meetingRecords[index].speakerTurns,
            overrides: meetingRecords[index].segmentSpeakerOverrides,
            speakers: meetingRecords[index].speakers
        )
        meetingRecords[index].transcript = merged.segments
        meetingRecords[index].speakers = merged.speakers
        persistMeeting(meetingRecords[index])
    }

    func restoreMeetingMinutesVersion(recordID: UUID, versionID: UUID) {
        ensureMeetingDetailLoaded(recordID)
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }),
              let versionIndex = meetingRecords[index].minutesVersions.firstIndex(where: { $0.id == versionID })
        else { return }
        let version = meetingRecords[index].minutesVersions[versionIndex]
        if let current = meetingRecords[index].summary {
            meetingRecords[index].minutesVersions.append(MeetingMinutesVersion(summary: current))
        }
        meetingRecords[index].minutesVersions.removeAll { $0.id == versionID }
        meetingRecords[index].summary = version.summary
        meetingRecords[index].status = .ready
        meetingRecords[index].summaryCheckpoint = nil
        meetingRecords[index].errorMessage = nil
        persistMeeting(meetingRecords[index])
    }

    func setMeetingCaptureMode(_ mode: MeetingCaptureMode) {
        meetingCaptureMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "jarvis.meeting.captureMode")
    }

    func createMeetingPlaceholder() {
        let id = UUID()
        let urls = meetingRepository.recordingURLs(for: id)
        let record = MeetingRecord(
            id: id,
            title: MeetingRecord.defaultTitle,
            audioFileName: urls.mixed.lastPathComponent,
            status: .failed,
            errorMessage: "识别资源还没准备好，这条会议先占着。资源下载完成后可以开始录音。",
            awaitingAssets: true
        )
        do {
            try meetingRepository.save(record)
            meetingRecords.insert(record, at: 0)
            selectedMeetingID = id
        } catch {
            showToast(JarvisFeedbackCopy.saveFailed)
        }
    }

    func postponeMeetingAssetDownload() {
        cancelMeetingModelPreparation()
        if !meetingRecords.contains(where: { $0.awaitingAssets == true }) {
            createMeetingPlaceholder()
        }
        showToast("资源稍后再准备。占位会议还不能录音。")
    }

    func pauseMeetingRecording() {
        guard meetingCurrentRecordingID != nil, !meetingRecordingPaused else { return }
        meetingElapsedAccumulated += Date().timeIntervalSince(meetingElapsedOrigin)
        meetingElapsed = meetingElapsedAccumulated
        meetingRecorder.pauseRecording()
        meetingRecordingPaused = true
        if let id = meetingCurrentRecordingID {
            persistClosedRecorderChunks(id)
        }
    }

    func resumeMeetingRecording() {
        guard meetingCurrentRecordingID != nil, meetingRecordingPaused else { return }
        do {
            try meetingRecorder.resumeRecording()
            meetingElapsedOrigin = Date()
            meetingRecordingPaused = false
        } catch {
            showToast(JarvisFeedbackCopy.recordingStartFailed)
        }
    }

    private func enqueueMeetingProcessing(
        recordID: UUID,
        kind: MeetingProcessingJob.Kind,
        preserveUserEdits: Bool = true
    ) {
        if meetingActiveProcessingID == recordID {
            return
        }
        let job = MeetingProcessingJob(
            recordID: recordID,
            kind: kind,
            preserveUserEdits: preserveUserEdits
        )
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
            startSummarizeTask(record, preserveUserEdits: job.preserveUserEdits)
        }
    }

    private func processMeeting(_ record: MeetingRecord) {
        meetingActiveProcessingID = record.id
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .transcribing
            meetingRecords[index].interruptedRecording = false
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
                let sourceRecord = meetingRecords.first { $0.id == record.id } ?? record
                let tracks = transcriptionTracks(
                    for: sourceRecord,
                    mixedURL: prepared.mixedURL,
                    systemAudioFileName: prepared.systemAudioFileName
                )
                let transcription = try await meetingTranscriptionService.transcribeTracks(
                    tracks,
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
                updatedRecord.speakerTurns = transcription.speakerTurns
                updatedRecord.diarizationDegraded = transcription.diarizationDegraded
                updatedRecord.diarizationDegradeReason = transcription.diarizationDegradeReason
                updatedRecord.estimatedSpeakerCount = transcription.estimatedSpeakerCount
                updatedRecord.uncertainSegmentRatio = transcription.uncertainSegmentRatio
                updatedRecord.systemAudioFileName = prepared.systemAudioFileName
                updatedRecord.errorMessage = transcription.diarizationDegraded
                    ? "说话人分离没有完成，逐字稿先不标说话人。纪要仍可生成。"
                    : nil
                if transcription.segments.isEmpty {
                    updatedRecord.status = .failed
                    updatedRecord.errorMessage = "未识别到有效语音，请检查音量后重新处理"
                    meetingRecords[currentIndex] = updatedRecord
                    persistMeeting(updatedRecord)
                    meetingProcessingState = .failed(updatedRecord.errorMessage ?? "")
                    showToast(JarvisFeedbackCopy.processingFailed)
                    return
                }

                updatedRecord.status = .transcribed
                meetingRecords[currentIndex] = updatedRecord
                persistMeeting(updatedRecord)

                let configuration = AIAPIConfiguration.load()
                guard configuration.isConfigured else {
                    meetingProcessingState = .awaitingConfiguration
                    showToast(JarvisFeedbackCopy.configureAIFirst)
                    return
                }
                guard MeetingTranscriptConsent.isConfirmed else {
                    meetingTranscriptConsentRecordID = updatedRecord.id
                    meetingProcessingState = .idle
                    return
                }
                try await performSummarize(updatedRecord, configuration: configuration, preserveUserEdits: true)
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func startSummarizeTask(_ record: MeetingRecord, preserveUserEdits: Bool = true) {
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
            showToast(JarvisFeedbackCopy.configureAIFirst)
            startNextMeetingProcessingIfNeeded()
            return
        }
        guard MeetingTranscriptConsent.isConfirmed else {
            meetingTranscriptConsentRecordID = record.id
            meetingProcessingState = .idle
            startNextMeetingProcessingIfNeeded()
            return
        }

        meetingActiveProcessingID = record.id
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: nil)
        meetingProcessingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { completeActiveMeetingProcessing(for: record.id) }
            do {
                try await performSummarize(
                    record,
                    configuration: configuration,
                    preserveUserEdits: preserveUserEdits
                )
            } catch is CancellationError {
                return
            } catch {
                updateMeetingFailure(recordID: record.id, message: error.localizedDescription)
            }
        }
    }

    private func performSummarize(
        _ record: MeetingRecord,
        configuration: AIAPIConfiguration,
        preserveUserEdits: Bool
    ) async throws {
        if let index = meetingRecords.firstIndex(where: { $0.id == record.id }) {
            meetingRecords[index].status = .summarizing
            persistMeeting(meetingRecords[index])
        }
        meetingProcessingState = .processing(stage: .summarizing, progress: nil)
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
            checkpoint: preserveUserEdits ? record.summaryCheckpoint : nil,
            preserveUserEdits: preserveUserEdits,
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
            },
            onProgress: { [weak self] progress in
                guard let self, self.meetingActiveProcessingID == record.id else { return }
                self.meetingProcessingState = .processing(stage: .summarizing, progress: progress)
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
        showToast(JarvisFeedbackCopy.summaryReady)
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
        _ = await assembleMeetingChunksIfCanonicalMissing(recordID: record.id)
        let source = meetingRecords.first { $0.id == record.id } ?? record
        let audioURL = try meetingRepository.audioURL(for: source)
        let microphoneURL = try meetingRepository.microphoneAudioURL(for: source)
        var systemAudioURL = try meetingRepository.systemAudioURL(for: source)
        var systemAudioFileName = source.systemAudioFileName
        let recordingURLs = meetingRepository.recordingURLs(for: source.id)

        if let currentSystemURL = systemAudioURL,
           currentSystemURL.pathExtension.lowercased() == "caf",
           MeetingAudioMixer.isReadyAudioFile(at: currentSystemURL)
        {
            do {
                try await MeetingAudioMixer.transcodeToM4A(
                    inputURL: currentSystemURL,
                    outputURL: recordingURLs.systemCompressed
                )
                systemAudioURL = recordingURLs.systemCompressed
                systemAudioFileName = recordingURLs.systemCompressed.lastPathComponent
                // Point the record at the m4a before deleting the caf, so a retry
                // does not look up a file that has already been removed.
                if let index = meetingRecords.firstIndex(where: { $0.id == source.id }) {
                    meetingRecords[index].systemAudioFileName = systemAudioFileName
                    persistMeeting(meetingRecords[index])
                }
                MeetingAudioMixer.removeFileIfExists(at: currentSystemURL)
            } catch {
                try await MeetingAudioMixer.makeMixedAudio(
                    microphoneURL: microphoneURL,
                    systemAudioURL: currentSystemURL,
                    outputURL: audioURL,
                    systemAudioDelay: source.resolvedSystemAudioStartOffset
                )
                return (audioURL, systemAudioFileName)
            }
        }

        try await MeetingAudioMixer.makeMixedAudio(
            microphoneURL: microphoneURL,
            systemAudioURL: systemAudioURL,
            outputURL: audioURL,
            systemAudioDelay: source.resolvedSystemAudioStartOffset
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
        record.audioChunks = result.chunks
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
        if let message = MeetingSystemAudioStopNotice.message(
            wroteSystemAudio: result.systemAudioStarted,
            failureMessage: result.systemAudioErrorMessage
        ) {
            showToast(message)
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
                ? JarvisFeedbackCopy.summaryFailed
                : JarvisFeedbackCopy.processingFailed
        )
    }

    private func transcriptionTracks(
        for record: MeetingRecord,
        mixedURL: URL,
        systemAudioFileName: String?
    ) -> [MeetingTranscriptionTrack] {
        let microphoneURL = (try? meetingRepository.microphoneAudioURL(for: record)) ?? mixedURL
        var tracks = [
            MeetingTranscriptionTrack(url: microphoneURL, timeOffset: 0, diarize: true, trackID: "mic")
        ]
        if record.resolvedCaptureMode == .dual,
           let systemURL = readySystemAudioURL(
               recordID: record.id,
               preferredFileName: systemAudioFileName ?? record.systemAudioFileName
           )
        {
            tracks.insert(
                MeetingTranscriptionTrack(
                    url: systemURL,
                    timeOffset: record.resolvedSystemAudioStartOffset,
                    diarize: true,
                    trackID: "system"
                ),
                at: 0
            )
        }
        return tracks
    }

    /// Prefer the name just produced by transcode, then the compressed m4a, then the caf.
    private func readySystemAudioURL(recordID: UUID, preferredFileName: String?) -> URL? {
        let urls = meetingRepository.recordingURLs(for: recordID)
        var candidates: [URL] = []
        if let preferredFileName {
            let preferred = meetingRepository.recordingsDirectoryURL
                .appendingPathComponent(preferredFileName, isDirectory: false)
            candidates.append(preferred)
        }
        candidates.append(urls.systemCompressed)
        candidates.append(urls.system)
        var seen = Set<String>()
        for url in candidates where seen.insert(url.path).inserted {
            if MeetingAudioMixer.isReadyAudioFile(at: url) {
                return url
            }
        }
        return nil
    }

    private func appendMeetingChunks(_ chunks: [MeetingAudioChunk], recordID: UUID) {
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else { return }
        for chunk in chunks {
            meetingRecords[index].audioChunks.removeAll { $0.kind == chunk.kind && $0.index == chunk.index }
            meetingRecords[index].audioChunks.append(chunk)
        }
        meetingRecords[index].audioChunks.sort { lhs, rhs in
            if lhs.kind == rhs.kind {
                return lhs.index < rhs.index
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        persistMeeting(meetingRecords[index])
    }

    func appendMeetingAudioEvent(_ event: MeetingAudioEvent) {
        guard let id = meetingCurrentRecordingID,
              let index = meetingRecords.firstIndex(where: { $0.id == id })
        else { return }
        meetingRecords[index].audioEvents.append(event)
        persistMeeting(meetingRecords[index])
        persistClosedRecorderChunks(id)
        showToast(event.message)
    }

    private func persistClosedRecorderChunks(_ id: UUID) {
        let chunks = meetingRecorder.closedChunksSnapshot()
        guard !chunks.isEmpty else { return }
        appendMeetingChunks(chunks, recordID: id)
    }

    private func reusableMeetingPlaceholder(recordID: UUID?) -> MeetingRecord? {
        let candidate = recordID ?? selectedMeetingID
        guard let candidate,
              let record = meetingRecords.first(where: { $0.id == candidate }),
              record.awaitingAssets == true
        else { return nil }
        return record
    }

    private func refreshMeetingRecordingMeters() {
        meetingMicrophonePower = meetingRecorder.microphoneAveragePower()
        meetingSystemPower = meetingRecorder.systemAveragePower()
        meetingBytesWritten = meetingRecorder.writtenByteCount()
    }

    private func warnIfSystemAudioStaysSilent() {
        guard meetingCaptureMode == .dual, !meetingDidWarnAboutSystemSilence, !meetingRecordingPaused else { return }
        guard let power = meetingRecorder.systemAveragePower() else { return }
        if power < -45 {
            if meetingSystemSilentSince == nil {
                meetingSystemSilentSince = Date()
            } else if let since = meetingSystemSilentSince, Date().timeIntervalSince(since) >= 30 {
                meetingDidWarnAboutSystemSilence = true
                showToast("系统音频已连续 30 秒没有声音，录音仍在继续")
            }
        } else {
            meetingSystemSilentSince = nil
        }
    }

    private func warnIfMeetingDiskIsLow() {
        let directory = meetingRepository.recordingsDirectoryURL
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values?.volumeAvailableCapacityForImportantUsage, bytes < 512 * 1024 * 1024 {
            showToast("磁盘剩余空间不足 512MB，录音可能写不完整")
        }
    }

    /// Builds canonical tracks from closed slices when stop() never finished that track.
    /// A playable microphone file does not skip system slices that are still on disk.
    private func assembleMeetingChunksIfCanonicalMissing(recordID: UUID) async -> Bool {
        let urls = meetingRepository.recordingURLs(for: recordID)
        let microphoneReady = await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
        let systemCAFReady = await MeetingAudioAssembler.playableDuration(at: urls.system) != nil
        let systemM4AReady = await MeetingAudioAssembler.playableDuration(at: urls.systemCompressed) != nil
        let systemReady = systemCAFReady || systemM4AReady
        let plan = MeetingCanonicalAssembly.plan(
            microphoneReady: microphoneReady,
            systemReady: systemReady
        )
        if !plan.assembleMicrophone && !plan.assembleSystem {
            return true
        }
        guard let record = meetingRecords.first(where: { $0.id == recordID }) else {
            return microphoneReady
        }
        let directory = urls.microphone.deletingLastPathComponent()
        let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let merged = MeetingAudioChunkFile.mergedChunks(
            stored: record.audioChunks,
            discovered: MeetingAudioChunkFile.discoveredChunks(meetingID: recordID, fileNames: fileNames)
        )
        let playable = await recoverableChunkFiles(merged, directory: directory)
        let microphone = plan.assembleMicrophone
            ? playable.filter { $0.chunk.kind == .microphone }
            : []
        let system = plan.assembleSystem
            ? playable.filter { $0.chunk.kind == .system }
            : []
        guard !microphone.isEmpty || !system.isEmpty else { return microphoneReady }

        var consumedNames = Set<String>()
        var assembledDuration: TimeInterval = 0
        if !microphone.isEmpty,
           let assembled = try? await MeetingAudioAssembler.concatenate(
               urls: microphone.map(\.url),
               outputURL: urls.microphone
           ),
           await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
        {
            assembledDuration = max(assembled, microphone.reduce(0) { $0 + $1.chunk.duration })
            consumedNames.formUnion(microphone.map(\.url.lastPathComponent))
        }
        var assembledSystemName: String?
        if !system.isEmpty,
           await (try? MeetingAudioAssembler.concatenate(
               urls: system.map(\.url),
               outputURL: urls.system
           )) != nil,
           await MeetingAudioAssembler.playableDuration(at: urls.system) != nil
        {
            assembledSystemName = urls.system.lastPathComponent
            consumedNames.formUnion(system.map(\.url.lastPathComponent))
        }
        guard let index = meetingRecords.firstIndex(where: { $0.id == recordID }) else {
            return await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
        }
        if assembledDuration > 0 {
            meetingRecords[index].microphoneAudioFileName = urls.microphone.lastPathComponent
            meetingRecords[index].duration = max(meetingRecords[index].duration, assembledDuration)
        }
        if let assembledSystemName {
            meetingRecords[index].systemAudioFileName = assembledSystemName
            if meetingRecords[index].captureMode == nil {
                meetingRecords[index].captureMode = .dual
            }
        }
        if !consumedNames.isEmpty {
            for name in consumedNames {
                let url = directory.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: url)
            }
            meetingRecords[index].audioChunks.removeAll { consumedNames.contains($0.fileName) }
            persistMeeting(meetingRecords[index])
        }
        return await MeetingAudioAssembler.playableDuration(at: urls.microphone) != nil
    }

    func recoverInterruptedMeetingAudio() async {
        let snapshot = meetingRecords.map { record in
            (id: record.id, interrupted: record.interruptedRecording == true)
        }
        for item in snapshot {
            let ready = await assembleMeetingChunksIfCanonicalMissing(recordID: item.id)
            guard item.interrupted, ready else { continue }
            guard let index = meetingRecords.firstIndex(where: { $0.id == item.id }) else { continue }
            let duration = meetingRecords[index].duration
            meetingRecords[index].status = .failed
            meetingRecords[index].interruptedRecording = true
            meetingRecords[index].errorMessage =
                "录音未正常结束，已保留约 \(MeetingRecordingStyle.formatDuration(duration))。可以手动继续处理，不会自动开始转写。"
            persistMeeting(meetingRecords[index])
        }
    }

    private func recoverableChunkFiles(
        _ chunks: [MeetingAudioChunk],
        directory: URL
    ) async -> [(chunk: MeetingAudioChunk, url: URL)] {
        var kept: [(MeetingAudioChunk, URL)] = []
        for chunk in chunks where MeetingAudioChunkFile.isChunkFileName(chunk.fileName) {
            let url = directory.appendingPathComponent(chunk.fileName)
            guard MeetingAudioMixer.isReadyAudioFile(at: url) else { continue }
            if chunk.closed {
                kept.append((chunk, url))
            } else if await MeetingAudioAssembler.playableDuration(at: url) != nil {
                kept.append((chunk, url))
            }
        }
        return kept
    }

    private func snapshotRecordingIfNeeded(_ id: UUID) {
        let bucket = Int(meetingElapsed / 30)
        guard bucket > 0, bucket != meetingRecoverySnapshotBucket else { return }
        meetingRecoverySnapshotBucket = bucket
        guard let index = meetingRecords.firstIndex(where: { $0.id == id }) else { return }
        meetingRecords[index].duration = meetingElapsed
        persistMeeting(meetingRecords[index])
    }

    private func warnIfMicrophoneStaysSilent() {
        guard !meetingDidWarnAboutSilence else { return }
        guard let power = meetingRecorder.microphoneAveragePower() else { return }
        if power < -45 {
            if meetingMicrophoneSilentSince == nil {
                meetingMicrophoneSilentSince = Date()
            } else if let since = meetingMicrophoneSilentSince, Date().timeIntervalSince(since) >= 30 {
                meetingDidWarnAboutSilence = true
                showToast("麦克风已连续 30 秒没有声音，录音仍在继续")
            }
        } else {
            meetingMicrophoneSilentSince = nil
        }
    }

    private func persistMeeting(_ record: MeetingRecord) {
        do {
            try meetingRepository.save(record)
        } catch {
            JarvisLog.error(
                category: .storage,
                event: "meeting.persist.failed",
                error: error,
                fields: ["meetingID": record.id.uuidString]
            )
            showToast(JarvisFeedbackCopy.saveFailed)
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
    var preserveUserEdits: Bool = true
}

private enum MeetingAudioFileError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "原始录音文件未完成保存，无法开始转写"
        }
    }
}
