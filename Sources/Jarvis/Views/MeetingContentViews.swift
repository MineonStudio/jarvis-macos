import AVFoundation
import Combine
import SwiftUI

private enum MeetingDetailTypography {
    static let h1 = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let h2 = Font.system(size: 20, weight: .semibold)
    static let h3 = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
}

struct MeetingView: View {
    @Environment(AppModel.self) private var app
    @State private var searchText = ""

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(id: "meeting.recording", placement: .navigation) {
                    recordingToolbarButton
                }
            },
            trailingToolbar: {
                ToolbarItem(id: "meeting.export", placement: .automatic) {
                    MeetingExportToolbar(record: selectedRecord)
                }
                ToolbarSpacer(.fixed, placement: .automatic)
                ToolbarItem(id: "meeting.search", placement: .automatic) {
                    ClipboardSearchField(
                        text: $searchText,
                        placeholder: "搜索会议",
                        focusesOnAppear: false
                    )
                }
            },
            content: {
                VStack(spacing: 0) {
                    if let storageError = app.meetingStorageError {
                        MeetingStorageErrorBanner(message: storageError)
                    }
                    if app.meetingRecords.isEmpty {
                        MeetingEmptyState()
                    } else {
                        HStack(spacing: 0) {
                            MeetingHistoryList(searchText: searchText)
                                .frame(width: 246)
                            Divider()
                            MeetingDetailPane(record: selectedRecord)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
        .onAppear {
            if app.selectedMeetingID == nil {
                app.selectedMeetingID = app.meetingRecords.first?.id
            }
            if let selectedMeetingID = app.selectedMeetingID {
                app.ensureMeetingDetailLoaded(selectedMeetingID)
            }
            app.refreshMeetingModelState()
        }
        .onChange(of: app.selectedMeetingID) { _, newValue in
            if let newValue {
                app.ensureMeetingDetailLoaded(newValue)
            }
        }
        .onChange(of: searchText) { _, _ in
            let filteredIDs = Set(filteredRecords.map(\.id))
            if let selectedMeetingID = app.selectedMeetingID,
               !filteredIDs.contains(selectedMeetingID)
            {
                app.selectedMeetingID = filteredRecords.first?.id
            }
        }
    }

    private var filteredRecords: [MeetingRecord] {
        MeetingHistoryList.filteredRecords(from: app.meetingRecords, searchText: searchText)
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
                Text(isRecording
                    ? MeetingRecordingStyle.displayTitle(for: app.meetingElapsed)
                    : "开始录制"
                )
                .font(isRecording ? MeetingRecordingStyle.font : JarvisTypography.control)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(
            JarvisToolbarButtonStyle.menu(
                tint: isRecording ? MeetingRecordingStyle.activeTint : nil
            )
        )
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
            .disabled(!app.meetingModelsReady)

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
                        Text("\(stage.title) \(Int(progress * 100))%")
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

private struct MeetingStorageErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

private struct MeetingExportToolbar: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord?

    private var canExport: Bool {
        record != nil
    }

    var body: some View {
        HStack(spacing: 2) {
            exportButton(
                systemName: "doc.on.doc",
                help: "复制纪要",
                isEnabled: canExport
            ) {
                guard let record else { return }
                app.copyMeetingMarkdown(record)
            }
            exportButton(
                systemName: "square.and.arrow.up",
                help: "导出 Markdown",
                isEnabled: canExport
            ) {
                guard let record else { return }
                app.exportMeetingMarkdown(record)
            }
        }
        .padding(4)
        .frame(height: JarvisToolbarMetrics.controlSize)
    }

    private func exportButton(
        systemName: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .opacity(isEnabled ? 1 : 0.38)
        .disabled(!isEnabled)
        .accessibilityLabel(help)
        .jarvisHoverFeedback(in: Circle(), scale: 1.06)
        .help(help)
    }
}

private struct MeetingHistoryList: View {
    @Environment(AppModel.self) private var app
    let searchText: String
    @State private var recordPendingDeletion: MeetingRecord?

    static func filteredRecords(from records: [MeetingRecord], searchText: String) -> [MeetingRecord] {
        records.filter { $0.matchesSearch(searchText) }
    }

    private var filteredRecords: [MeetingRecord] {
        Self.filteredRecords(from: app.meetingRecords, searchText: searchText)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                HStack {
                    Text("会议记录")
                        .font(JarvisTypography.bodyEmphasis)
                    Spacer()
                    Text("\(filteredRecords.count)")
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                if filteredRecords.isEmpty {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "还没有会议记录"
                        : "没有匹配的会议")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                }

                ForEach(filteredRecords) { record in
                    MeetingHistoryRow(
                        record: record,
                        isSelected: app.selectedMeetingID == record.id
                    ) {
                        app.selectedMeetingID = record.id
                    }
                    .contextMenu {
                        if app.meetingCurrentRecordingID == record.id {
                            Button("停止并仅保存录音") {
                                app.cancelMeetingRecording()
                            }
                        }
                        Button("复制纪要") {
                            app.copyMeetingMarkdown(record)
                        }
                        Button("删除会议", role: .destructive) {
                            recordPendingDeletion = record
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .background(Color.jarvisPanel.opacity(0.34))
        .confirmationDialog(
            "删除会议",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: {
                    if !$0 {
                        recordPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let recordPendingDeletion {
                    app.deleteMeeting(recordPendingDeletion)
                }
                recordPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                recordPendingDeletion = nil
            }
        } message: {
            Text("将同时删除本机保存的原始录音和逐字稿，且无法恢复。")
        }
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
                    Text(record.title)
                        .font(JarvisTypography.controlEmphasis)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatMeetingListDateTime(record.createdAt))
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
        .accessibilityLabel("\(record.title)，\(formatMeetingListDateTime(record.createdAt))")
    }
}

private struct MeetingDetailPane: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isTitleFocused: Bool
    @State private var isTitleHovered = false
    @State private var draftTitle = ""
    @State private var pendingSeekTime: TimeInterval?
    let record: MeetingRecord?

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        meetingHeader(record)

                        MeetingAudioSection(record: record, pendingSeekTime: $pendingSeekTime)

                        if shouldShowProgress(for: record) {
                            MeetingProcessingCard(state: app.meetingProcessingState)
                        }

                        if record.status == .failed || record.status == .summaryFailed,
                           let errorMessage = record.errorMessage
                        {
                            MeetingFailureCard(record: record, message: errorMessage)
                        }

                        if let summary = record.summary {
                            MeetingSummarySection(summary: summary)
                        } else if !record.transcript.isEmpty,
                                  record.status != .summarizing,
                                  record.status != .failed,
                                  record.status != .summaryFailed
                        {
                            MeetingNeedsSummaryCard(record: record)
                        }

                        if !record.speakers.isEmpty {
                            MeetingSpeakerSection(record: record)
                        }

                        if !record.transcript.isEmpty {
                            MeetingTranscriptSection(record: record) { time in
                                pendingSeekTime = time
                            }
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
            isTitleFocused = false
        }
        .onChange(of: isTitleFocused) { _, isFocused in
            if !isFocused {
                commitTitle()
            }
        }
    }

    private func meetingHeader(_ record: MeetingRecord) -> some View {
        let displayTitle = draftTitle.isEmpty ? MeetingRecord.defaultTitle : draftTitle

        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                Text(displayTitle)
                    .font(MeetingDetailTypography.h1)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, MeetingTitleMetrics.horizontalPadding)
                    .padding(.vertical, MeetingTitleMetrics.verticalPadding)
                    .opacity(0)

                TextField("", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(MeetingDetailTypography.h1)
                    .lineLimit(1)
                    .focused($isTitleFocused)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, MeetingTitleMetrics.horizontalPadding)
                    .padding(.vertical, MeetingTitleMetrics.verticalPadding)
                    .accessibilityLabel("会议名称")
            }
            .contentShape(Capsule())
            .onTapGesture {
                isTitleFocused = true
            }
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay {
                if isTitleFocused || isTitleHovered {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .onHover { isTitleHovered = $0 }
            .background(
                MeetingTitleOutsideClickMonitor(isFocused: isTitleFocused) {
                    isTitleFocused = false
                }
            )
            .help("点击修改会议名称")

            HStack(spacing: 12) {
                Label(formatMeetingDateTime(record.createdAt), systemImage: "calendar")
                Label(formatMeetingDuration(record.duration), systemImage: "clock")
                Text(record.status.title)
                    .foregroundStyle(headerStatusColor(record.status))
            }
            .font(JarvisTypography.caption)
            .foregroundStyle(Color.jarvisTextSecondary)
        }
    }

    private func headerStatusColor(_ status: MeetingRecordStatus) -> Color {
        switch status {
        case .recording, .failed, .summaryFailed: .red
        case .transcribing, .summarizing: .orange
        case .transcribed: Color.jarvisTextSecondary
        case .ready: .green
        }
    }

    private func commitTitle() {
        guard let record else { return }
        app.updateMeetingTitle(recordID: record.id, title: draftTitle)
        draftTitle = app.meetingRecords.first(where: { $0.id == record.id })?.title ?? MeetingRecord.defaultTitle
    }

    private func shouldShowProgress(for record: MeetingRecord) -> Bool {
        switch record.status {
        case .recording, .transcribing, .summarizing:
            true
        case .transcribed, .summaryFailed, .ready, .failed:
            false
        }
    }
}

private enum MeetingTitleMetrics {
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 7
}

private struct MeetingTitleOutsideClickMonitor: NSViewRepresentable {
    let isFocused: Bool
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView(frame: .zero)
        context.coordinator.update(view: view, isFocused: isFocused) {
            onDismiss()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(view: nsView, isFocused: isFocused) {
            onDismiss()
        }
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private final class PassthroughView: NSView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        private var monitor: Any?
        private var dismiss: (() -> Void)?

        func update(view: NSView, isFocused: Bool, dismiss: @escaping () -> Void) {
            self.view = view
            self.dismiss = dismiss
            if isFocused {
                startIfNeeded()
            } else {
                stop()
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func startIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self, let view = self.view, let titleWindow = view.window else { return event }
                guard event.window === titleWindow else {
                    self.dismiss?()
                    return event
                }
                let pointInView = view.convert(event.locationInWindow, from: nil)
                if !view.bounds.contains(pointInView) {
                    self.dismiss?()
                }
                return event
            }
        }
    }
}

private struct MeetingAudioSection: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    @Binding var pendingSeekTime: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetingSectionHeader(title: "原始录音", systemImage: "waveform")
            let isRecording = app.meetingCurrentRecordingID == record.id

            if isRecording {
                MeetingAudioPlayer(
                    title: "原始录音",
                    audioURL: app.meetingMicrophoneAudioURL(for: record),
                    isRecording: true,
                    recordingElapsed: app.meetingElapsed,
                    pendingSeekTime: $pendingSeekTime
                )
            } else {
                MeetingAudioPlayer(
                    title: "原始录音",
                    audioURL: app.meetingAudioURL(for: record),
                    isRecording: false,
                    recordingElapsed: 0,
                    pendingSeekTime: $pendingSeekTime
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
    @Binding var pendingSeekTime: TimeInterval?
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
                            Text("正在录音")
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
                        .accessibilityLabel("原始录音进度")
                        .accessibilityValue(
                            "\(formatMeetingDuration(controller.currentTime)) / "
                                + formatMeetingDuration(controller.duration)
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
                        Text("正在保存录音")
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
                        Text("录音暂不可用")
                            .font(JarvisTypography.bodyEmphasis)
                        Text("未找到本机录音文件，会议文字内容仍会保留")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            }
        }
        .onAppear {
            if !isRecording {
                controller.load(url: audioURL)
            }
        }
        .onChange(of: audioURL) { _, newValue in
            if !isRecording {
                controller.load(url: newValue)
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if !newValue {
                controller.load(url: audioURL, force: true)
            }
        }
        .onChange(of: pendingSeekTime) { _, newValue in
            guard let newValue, !isRecording else { return }
            controller.seek(to: newValue)
            if !controller.isPlaying {
                controller.togglePlayback()
            }
            pendingSeekTime = nil
        }
        .onReceive(playbackTimer) { _ in
            guard !isRecording else { return }
            controller.refreshAvailability()
            controller.refreshProgress()
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

private struct MeetingFailureCard: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    let message: String

    var body: some View {
        JarvisCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.status == .summaryFailed ? "会议纪要生成失败" : "处理失败")
                        .font(JarvisTypography.bodyEmphasis)
                    Text(message)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if record.canRetryProcessing {
                    Button(record.status == .summaryFailed ? "重新生成纪要" : "重新处理") {
                        app.selectedMeetingID = record.id
                        app.retryMeetingProcessing(record)
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                }
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
                    Text("转写已完成")
                        .font(JarvisTypography.bodyEmphasis)
                    Text("现在可以生成一份以结论和待办为中心的会议总结。")
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
                            .font(MeetingDetailTypography.body)
                            .lineSpacing(5)
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
                    .font(MeetingDetailTypography.h3)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)
                        Text(item)
                            .font(MeetingDetailTypography.body)
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
                    .font(MeetingDetailTypography.h3)
                ForEach(summary.actionItems) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.task)
                            .font(MeetingDetailTypography.body)
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
    let record: MeetingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetingSectionHeader(title: "说话人", systemImage: "person.2")
            MeetingChipFlowLayout(spacing: 8) {
                ForEach(record.speakers) { speaker in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(speakerColor(speaker.colorIndex))
                            .frame(width: 8, height: 8)
                        Text(speaker.name)
                            .font(MeetingDetailTypography.h3)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.jarvisPanel, in: Capsule())
                }
            }
        }
    }
}

private struct MeetingTranscriptSection: View {
    let record: MeetingRecord
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MeetingSectionHeader(title: "逐字稿", systemImage: "text.quote")
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(record.transcript) { segment in
                    let speaker = record.speakers.first { $0.id == segment.speakerID }
                    Button {
                        onSeek(segment.startTime)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(speakerColor(speaker?.colorIndex ?? 0))
                                .frame(width: 9, height: 9)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(speaker?.name ?? segment.speakerID)
                                        .font(MeetingDetailTypography.h3)
                                    Text(formatMeetingTimestamp(segment.startTime))
                                        .font(JarvisTypography.monospaced)
                                        .foregroundStyle(Color.jarvisTextSecondary)
                                }
                                Text(segment.text)
                                    .font(MeetingDetailTypography.body)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("跳转到 \(formatMeetingTimestamp(segment.startTime))")
                    .accessibilityLabel("从\(formatMeetingTimestamp(segment.startTime))开始播放")
                    if segment.id != record.transcript.last?.id {
                        Divider().opacity(0.55)
                    }
                }
            }
            .padding(.horizontal, 16)
            .jarvisContentSurface(cornerRadius: JarvisMetrics.cardRadius)
        }
    }
}

private func formatMeetingDuration(_ duration: TimeInterval) -> String {
    MeetingRecordingStyle.formatDuration(duration)
}

private func formatMeetingDateTime(_ date: Date) -> String {
    date.formatted(
        .dateTime
            .year()
            .month()
            .day()
            .hour()
            .minute()
            .second()
            .locale(Locale(identifier: "zh_CN"))
    )
}

private func formatMeetingListDateTime(_ date: Date) -> String {
    date.formatted(
        .dateTime
            .year()
            .month()
            .day()
            .hour()
            .minute()
            .locale(Locale(identifier: "zh_CN"))
    )
}

private struct MeetingSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(MeetingDetailTypography.h2)
            .accessibilityAddTraits(.isHeader)
    }
}

private func formatMeetingTimestamp(_ time: TimeInterval) -> String {
    MeetingRecordingStyle.formatTimestamp(time)
}

private func speakerColor(_ index: Int) -> Color {
    [Color.accentColor, .purple, .orange, .green, .pink, .indigo][index % 6]
}

private struct MeetingChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = arrange(in: bounds.width, subviews: subviews).frames
        for (index, frame) in frames.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let availableWidth = max(width, 1)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: max(maxX, availableWidth), height: y + rowHeight), frames)
    }
}
