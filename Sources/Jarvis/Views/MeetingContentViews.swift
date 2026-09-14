import AVFoundation
import SwiftUI

struct MeetingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItemGroup(placement: .navigation) {}
            },
            trailingToolbar: {
                JarvisToolbarSurface(id: "meeting.recording", placement: .primaryAction) {
                    recordingToolbarButton
                }
            },
            content: {
                Group {
                    if app.meetingRecords.isEmpty {
                        MeetingEmptyState()
                    } else {
                        HStack(spacing: 0) {
                            MeetingHistoryList()
                                .frame(width: 246)
                            Divider()
                            MeetingDetailPane(record: selectedRecord)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .onAppear {
            if app.selectedMeetingID == nil {
                app.selectedMeetingID = app.meetingRecords.first?.id
            }
            app.refreshMeetingModelState()
        }
    }

    private var selectedRecord: MeetingRecord? {
        guard let selectedMeetingID = app.selectedMeetingID else {
            return app.meetingRecords.first
        }
        return app.meetingRecords.first { $0.id == selectedMeetingID }
            ?? app.meetingRecords.first
    }

    @ViewBuilder
    private var recordingToolbarButton: some View {
        let isRecording = app.meetingCurrentRecordingID != nil
        Button {
            app.toggleMeetingRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                Text(
                    isRecording
                        ? MeetingRecordingStyle.displayTitle(for: app.meetingElapsed)
                        : "开始录制"
                )
                .font(isRecording ? MeetingRecordingStyle.font : JarvisTypography.controlEmphasis)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isRecording ? MeetingRecordingStyle.foregroundColor : Color.accentColor)
        .padding(.horizontal, isRecording ? MeetingRecordingStyle.horizontalPadding : 12)
        .frame(
            minHeight: isRecording
                ? MeetingRecordingStyle.controlHeight
                : JarvisToolbarMetrics.controlSize
        )
        .background(
            isRecording
                ? MeetingRecordingStyle.backgroundColor
                : Color.accentColor.opacity(MeetingRecordingStyle.idleBackgroundOpacity),
            in: Capsule()
        )
        .contentShape(Capsule())
        .help(
            isRecording
                ? "结束录音并开始整理会议"
                : (app.meetingModelsReady ? "开始新的会议录音" : "首次使用前请先下载会议识别模型")
        )
        .accessibilityLabel(
            isRecording
                ? "结束录音，已录制 \(MeetingRecordingStyle.formatDuration(app.meetingElapsed))"
                : "开始录制"
        )
    }
}

private struct MeetingEmptyState: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.person.filled")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 76, height: 76)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))

            VStack(spacing: 8) {
                Text("把一次会议，变成可执行的结论")
                    .font(JarvisTypography.pageTitle)
                Text("录音结束后，Jarvis 会在本地完成转写和说话人分段，再生成 AI 总结。")
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if !app.meetingModelsReady {
                MeetingModelDownloadPrompt()
            }

            Button {
                Task { await app.startMeetingRecording() }
            } label: {
                Label("开始第一次录音", systemImage: "record.circle.fill")
                    .frame(minWidth: 150)
            }
            .buttonStyle(JarvisPrimaryButtonStyle())

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("原始录音与逐字稿保存在本机；总结使用设置中的 AI 服务")
            }
            .font(JarvisTypography.caption)
            .foregroundStyle(Color.jarvisTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct MeetingModelDownloadPrompt: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Color.accentColor)
                    Text("首次使用需要下载本地识别模型")
                        .font(JarvisTypography.bodyEmphasis)
                }
                Text("包含说话人识别和中文转写模型，约占用 650 MB。下载完成后再开始录音。")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)

                if case let .downloading(stage, progress) = app.meetingModelState {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(Color.accentColor)
                        Text("\(stage.title) (Int(progress * 100))%")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    Button("取消下载") {
                        app.cancelMeetingModelPreparation()
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                } else {
                    Button("下载识别模型") {
                        app.prepareMeetingModels()
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                }
            }
        }
        .frame(maxWidth: 520)
    }
}

private struct MeetingHistoryList: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                HStack {
                    Text("会议记录")
                        .font(JarvisTypography.bodyEmphasis)
                    Spacer()
                    Text("\(app.meetingRecords.count)")
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                ForEach(app.meetingRecords) { record in
                    MeetingHistoryRow(
                        record: record,
                        isSelected: app.selectedMeetingID == record.id
                    ) {
                        app.selectedMeetingID = record.id
                    }
                    .contextMenu {
                        Button("删除会议", role: .destructive) {
                            app.deleteMeeting(record)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(Color.jarvisPanel.opacity(0.34))
    }
}

private struct MeetingHistoryRow: View {
    let record: MeetingRecord
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Keep the button's hit target as wide as its visible row.
                // A content-shaped VStack alone can leave the blank part of the
                // selected background outside the native Button hit region.
                Color.clear

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(statusColor)
                        Text(record.title)
                            .font(JarvisTypography.controlEmphasis)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        Text(record.createdAt, style: .date)
                        Text("·")
                        Text(formatMeetingDuration(record.duration))
                    }
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("\(record.title)，\(record.status.title)")
    }

    private var statusIcon: String {
        switch record.status {
        case .recording: "record.circle.fill"
        case .transcribing, .summarizing: "ellipsis.circle"
        case .transcribed: "doc.text"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .recording, .failed: .red
        case .transcribing, .summarizing: .orange
        case .transcribed: .secondary
        case .ready: .green
        }
    }
}

private struct MeetingDetailPane: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isTitleFocused: Bool
    @State private var draftTitle = ""
    let record: MeetingRecord?

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        meetingHeader(record)

                        MeetingAudioSection(record: record)

                        if shouldShowProgress(for: record) {
                            MeetingProcessingCard(state: app.meetingProcessingState)
                        }

                        if let summary = record.summary {
                            MeetingSummarySection(summary: summary)
                        } else if !record.transcript.isEmpty {
                            MeetingNeedsSummaryCard(record: record)
                        }

                        if !record.speakers.isEmpty {
                            MeetingSpeakerSection(record: record)
                        }

                        if !record.transcript.isEmpty {
                            MeetingTranscriptSection(record: record)
                        } else if !shouldShowProgress(for: record) {
                            JarvisEmptyState(
                                icon: "waveform",
                                title: "还没有逐字稿",
                                message: "结束录音后，Jarvis 会自动处理这段会议。"
                            )
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JarvisMetrics.pageInset)
                }
            } else {
                Text("选择一条会议记录")
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.jarvisBackground)
        .onAppear {
            draftTitle = record?.title ?? ""
        }
        .onChange(of: record?.id) { _, _ in
            draftTitle = record?.title ?? ""
        }
        .onChange(of: isTitleFocused) { _, isFocused in
            if !isFocused {
                commitTitle()
            }
        }
    }

    private func meetingHeader(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                TextField("未命名会议", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(JarvisTypography.pageTitle)
                    .lineLimit(1)
                    .focused($isTitleFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .onSubmit {
                        commitTitle()
                        isTitleFocused = false
                    }
                    .help("点击修改会议名称")
                Spacer()
                Text(record.status.title)
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(record.status == .ready ? .green : Color.jarvisTextSecondary)
            }
            HStack(spacing: 12) {
                Label(record.createdAt.formatted(date: .long, time: .shortened), systemImage: "calendar")
                Label(formatMeetingDuration(record.duration), systemImage: "clock")
                Label(record.language.title, systemImage: "character.book.closed")
            }
            .font(JarvisTypography.caption)
            .foregroundStyle(Color.jarvisTextSecondary)
        }
    }

    private func commitTitle() {
        guard let record else { return }
        app.updateMeetingTitle(recordID: record.id, title: draftTitle)
        draftTitle = app.meetingRecords.first(where: { $0.id == record.id })?.title ?? MeetingRecord.defaultTitle
    }

    private func shouldShowProgress(for record: MeetingRecord) -> Bool {
        record.id == app.selectedMeetingID && {
            if case .processing = app.meetingProcessingState {
                return true
            }
            return record.status == .recording
        }()
    }
}

private struct MeetingAudioSection: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetingSectionHeader(title: "原始录音", systemImage: "waveform")
            let isRecording = app.meetingCurrentRecordingID == record.id

            if isRecording {
                MeetingAudioPlayer(
                    title: "原始录音",
                    audioURL: app.meetingMicrophoneAudioURL(for: record),
                    isRecording: true,
                    recordingElapsed: app.meetingElapsed
                )
            } else {
                MeetingAudioPlayer(
                    title: "原始录音",
                    audioURL: app.meetingAudioURL(for: record),
                    isRecording: false,
                    recordingElapsed: 0
                )
            }
        }
    }
}

@MainActor
private final class MeetingAudioPlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isAvailable = false
    @Published private(set) var isChecking = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var loadedURL: URL?
    private var availabilityCheckStartedAt: Date?
    private let availabilityGracePeriod: TimeInterval = 8

    func load(url: URL?, force: Bool = false) {
        guard force || loadedURL != url else {
            refreshAvailability()
            return
        }

        resetPlayback()
        loadedURL = url
        guard let url else {
            isAvailable = false
            isChecking = false
            return
        }
        availabilityCheckStartedAt = Date()
        isChecking = true
        attemptLoad(url)
    }

    private func attemptLoad(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            isAvailable = false
            finishAvailabilityCheckIfNeeded()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayer = player
            duration = player.duration
            isAvailable = true
            isChecking = false
            availabilityCheckStartedAt = nil
        } catch {
            isAvailable = false
            finishAvailabilityCheckIfNeeded()
        }
    }

    func refreshAvailability() {
        guard !isAvailable, let loadedURL else { return }
        attemptLoad(loadedURL)
    }

    private func finishAvailabilityCheckIfNeeded() {
        guard let availabilityCheckStartedAt else { return }
        if Date().timeIntervalSince(availabilityCheckStartedAt) >= availabilityGracePeriod {
            isChecking = false
        }
    }

    func togglePlayback() {
        guard let audioPlayer else { return }
        if audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlaying = false
        } else {
            if currentTime >= duration {
                currentTime = 0
            }
            audioPlayer.currentTime = currentTime
            audioPlayer.play()
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        let boundedTime = min(max(0, time), max(duration, 0))
        audioPlayer.currentTime = boundedTime
        currentTime = boundedTime
    }

    func stop() {
        resetPlayback()
        loadedURL = nil
        availabilityCheckStartedAt = nil
        isChecking = false
    }

    private func resetPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isAvailable = false
    }

    func refreshProgress() {
        guard let audioPlayer else { return }
        currentTime = audioPlayer.currentTime
        if !audioPlayer.isPlaying, isPlaying {
            if currentTime >= duration {
                currentTime = 0
            }
            isPlaying = false
        }
    }
}

private struct MeetingAudioPlayer: View {
    let title: String
    let audioURL: URL?
    let isRecording: Bool
    let recordingElapsed: TimeInterval
    @StateObject private var controller = MeetingAudioPlaybackController()
    private let playbackTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        JarvisCard {
            if isRecording {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.red)
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(title) · 正在录音")
                                .font(JarvisTypography.bodyEmphasis)
                            Text("原始音频正在本机写入，录音结束后即可播放")
                                .font(JarvisTypography.caption)
                                .foregroundStyle(Color.jarvisTextSecondary)
                        }

                        Spacer(minLength: 12)
                        Text(formatMeetingDuration(recordingElapsed))
                            .font(JarvisTypography.monospaced)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            } else if controller.isAvailable {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(title)
                            .font(JarvisTypography.bodyEmphasis)
                        Spacer(minLength: 8)
                        Button {
                            controller.togglePlayback()
                        } label: {
                            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(JarvisPrimaryButtonStyle())
                        .accessibilityLabel(controller.isPlaying ? "暂停原始录音" : "播放原始录音")

                        Slider(
                            value: Binding(
                                get: { controller.currentTime },
                                set: { controller.seek(to: $0) }
                            ),
                            in: 0 ... max(controller.duration, 1)
                        )

                        Text(formatMeetingDuration(controller.currentTime))
                            .font(JarvisTypography.monospaced)
                            .foregroundStyle(Color.jarvisTextSecondary)

                        Text("/ \(formatMeetingDuration(controller.duration))")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            } else if controller.isChecking {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("正在保存\(title)")
                            .font(JarvisTypography.bodyEmphasis)
                        Text("音频文件正在完成写入，请稍候")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(title)暂不可用")
                            .font(JarvisTypography.bodyEmphasis)
                        Text("未找到本机录音文件，会议文字内容仍会保留")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            }
        }
        .onAppear {
            controller.load(url: audioURL)
        }
        .onChange(of: audioURL) { _, newValue in
            controller.load(url: newValue)
        }
        .onChange(of: isRecording) { _, newValue in
            if !newValue {
                controller.load(url: audioURL, force: true)
            }
        }
        .onReceive(playbackTimer) { _ in
            if isRecording {
                controller.refreshAvailability()
            } else {
                controller.refreshAvailability()
                controller.refreshProgress()
            }
        }
        .onDisappear {
            controller.stop()
        }
    }
}

private struct MeetingProcessingCard: View {
    let state: MeetingProcessingState

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(state.title)
                        .font(JarvisTypography.bodyEmphasis)
                    Spacer()
                    if case let .processing(_, progress) = state {
                        Text("\(Int(progress * 100))%")
                            .font(JarvisTypography.monospaced)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
                if case let .processing(_, progress) = state {
                    ProgressView(value: progress)
                        .tint(Color.accentColor)
                }
                Text("原始音频文件会保留在本机；只有你主动删除会议时才会删除。")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
    }
}

private struct MeetingNeedsSummaryCard: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord

    var body: some View {
        JarvisCard {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("逐字稿已完成")
                        .font(JarvisTypography.bodyEmphasis)
                    Text("现在生成一份以结论和待办为中心的会议总结。")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                Spacer()
                Button("生成总结") {
                    app.selectedMeetingID = record.id
                    app.summarizeSelectedMeeting()
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
            }
        }
    }
}

private struct MeetingSummarySection: View {
    let summary: MeetingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MeetingSectionHeader(title: "会议总结", systemImage: "sparkles")
            JarvisCard {
                VStack(alignment: .leading, spacing: 18) {
                    if !summary.overview.isEmpty {
                        Text(summary.overview)
                            .font(JarvisTypography.bodyEmphasis)
                            .lineSpacing(4)
                    }
                    summaryList(title: "关键讨论", icon: "list.bullet", items: summary.keyPoints)
                    summaryList(title: "明确决策", icon: "checkmark.seal", items: summary.decisions)
                    actionList
                    summaryList(title: "未解决问题", icon: "questionmark.circle", items: summary.openQuestions)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryList(title: String, icon: String, items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(JarvisTypography.controlEmphasis)
                    .foregroundStyle(Color.jarvisTextSecondary)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(item)
                            .font(JarvisTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionList: some View {
        if !summary.actionItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("待办事项", systemImage: "checklist")
                    .font(JarvisTypography.controlEmphasis)
                    .foregroundStyle(Color.jarvisTextSecondary)
                ForEach(summary.actionItems) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.task)
                            .font(JarvisTypography.body)
                        HStack(spacing: 8) {
                            if !item.owner.isEmpty {
                                Text("负责人：\(item.owner)")
                            }
                            if !item.dueDate.isEmpty {
                                Text("截止：\(item.dueDate)")
                            }
                        }
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct MeetingSpeakerSection: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    @State private var editingSpeakerID: String?
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetingSectionHeader(title: "说话人", systemImage: "person.2")
            HStack(spacing: 8) {
                ForEach(record.speakers) { speaker in
                    if editingSpeakerID == speaker.id {
                        TextField("说话人名称", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit(saveSpeakerName)
                    } else {
                        Button {
                            editingSpeakerID = speaker.id
                            draftName = speaker.name
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(speakerColor(speaker.colorIndex))
                                    .frame(width: 8, height: 8)
                                Text(speaker.name)
                                    .font(JarvisTypography.captionEmphasis)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.jarvisPanel, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("点击重命名说话人")
                        .accessibilityLabel("重命名\(speaker.name)")
                    }
                }
            }
        }
        .onChange(of: record.id) { _, _ in
            editingSpeakerID = nil
        }
    }

    private func saveSpeakerName() {
        guard let editingSpeakerID else { return }
        app.updateMeetingSpeakerName(
            recordID: record.id,
            speakerID: editingSpeakerID,
            name: draftName
        )
        self.editingSpeakerID = nil
    }
}

private struct MeetingTranscriptSection: View {
    let record: MeetingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetingSectionHeader(title: "逐字稿", systemImage: "text.quote")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(record.transcript) { segment in
                    let speaker = record.speakers.first { $0.id == segment.speakerID }
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(speakerColor(speaker?.colorIndex ?? 0))
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(speaker?.name ?? segment.speakerID)
                                    .font(JarvisTypography.captionEmphasis)
                                Text(formatMeetingTimestamp(segment.startTime))
                                    .font(JarvisTypography.monospaced)
                                    .foregroundStyle(Color.jarvisTextSecondary)
                            }
                            Text(segment.text)
                                .font(JarvisTypography.body)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 12)
                    if segment.id != record.transcript.last?.id {
                        Divider().opacity(0.55)
                    }
                }
            }
            .padding(.horizontal, 16)
            .jarvisGlass(cornerRadius: JarvisMetrics.cardRadius, interactive: false)
        }
    }
}

private func formatMeetingDuration(_ duration: TimeInterval) -> String {
    let total = max(0, Int(duration.rounded()))
    return total >= 3600
        ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        : String(format: "%02d:%02d", total / 60, total % 60)
}

private struct MeetingSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(JarvisTypography.bodyEmphasis)
    }
}

private func formatMeetingTimestamp(_ time: TimeInterval) -> String {
    let total = max(0, Int(time.rounded()))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

private func speakerColor(_ index: Int) -> Color {
    [Color.accentColor, .purple, .orange, .green, .pink, .indigo][index % 6]
}
