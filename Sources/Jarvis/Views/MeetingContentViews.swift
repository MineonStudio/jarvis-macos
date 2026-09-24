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
    @State private var searchMatchedRecordIDs: Set<UUID>?

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(id: "meeting.recording", placement: .navigation) {
                    recordingToolbarButton
                }
            },
            trailingToolbar: {
                ToolbarItem(id: "meeting.copy", placement: .automatic) {
                    MeetingCopyToolbar(record: selectedRecord)
                }
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

                    Group {
                        if app.meetingRecords.isEmpty {
                            MeetingEmptyState()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .jarvisModulePanel()
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                MeetingHistoryList(
                                    searchText: searchText,
                                    matchedRecordIDs: searchMatchedRecordIDs
                                )
                                .frame(width: 246)
                                .frame(maxHeight: .infinity)
                                .jarvisModulePanel()

                                MeetingDetailPane(
                                    record: selectedRecord,
                                    isSearchEmpty: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        && filteredRecords.isEmpty
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .jarvisModulePanel()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            searchMatchedRecordIDs = nil
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let immediateMatches = app.meetingRecords.filter { $0.matchesSearch(query) }
            if let selectedMeetingID = app.selectedMeetingID,
               !immediateMatches.contains(where: { $0.id == selectedMeetingID })
            {
                app.selectedMeetingID = nil
            }
        }
        .task(id: searchText) {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                searchMatchedRecordIDs = nil
                if app.selectedMeetingID == nil {
                    app.selectedMeetingID = app.meetingRecords.first?.id
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let matches = await app.matchingMeetingIDs(searchText: query)
            guard !Task.isCancelled, query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return
            }
            searchMatchedRecordIDs = matches
            if let selectedMeetingID = app.selectedMeetingID, !matches.contains(selectedMeetingID) {
                app.selectedMeetingID = filteredRecords.first?.id
            }
        }
    }

    private var filteredRecords: [MeetingRecord] {
        MeetingHistoryList.filteredRecords(
            from: app.meetingRecords,
            searchText: searchText,
            matchedRecordIDs: searchMatchedRecordIDs
        )
    }

    private var selectedRecord: MeetingRecord? {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let selectedMeetingID = app.selectedMeetingID else { return nil }
            return filteredRecords.first { $0.id == selectedMeetingID }
        }
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
                .foregroundStyle(Color.jarvisAccent)
                .frame(width: 76, height: 76)
                .background(Color.jarvisAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))

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
                        .foregroundStyle(Color.jarvisAccent)
                    Text("首次使用需要下载本地识别模型")
                        .font(JarvisTypography.bodyEmphasis)
                }
                Text("包含说话人识别和中文转写模型，约占用 650 MB。下载完成后再开始录音。")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)

                if case let .downloading(stage, progress) = app.meetingModelState {
                    HStack(spacing: 8) {
                        ProgressView(value: progress)
                            .tint(Color.jarvisAccent)
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
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

private struct MeetingCopyToolbar: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord?

    private var canCopy: Bool {
        record != nil
    }

    var body: some View {
        Menu {
            if let record {
                Button("复制精简纪要") {
                    app.copyMeetingMarkdown(record)
                }
                Button("复制完整记录") {
                    app.copyMeetingMarkdown(record, includeTranscript: true)
                }
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .disabled(!canCopy)
        .accessibilityLabel("复制会议内容")
        .padding(4)
        .frame(height: JarvisToolbarMetrics.controlSize)
    }
}

private struct MeetingExportToolbar: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord?

    var body: some View {
        Menu {
            if let record {
                Button("导出精简纪要…") {
                    app.exportMeetingMarkdown(record)
                }
                Button("导出完整记录…") {
                    app.exportMeetingMarkdown(record, includeTranscript: true)
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: JarvisToolbarMetrics.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(JarvisToolbarIconButtonStyle())
        .disabled(record == nil)
        .accessibilityLabel("导出会议内容")
        .padding(4)
        .frame(height: JarvisToolbarMetrics.controlSize)
    }
}

private struct MeetingHistoryList: View {
    @Environment(AppModel.self) private var app
    let searchText: String
    let matchedRecordIDs: Set<UUID>?
    @State private var recordPendingDeletion: MeetingRecord?

    static func filteredRecords(
        from records: [MeetingRecord],
        searchText: String,
        matchedRecordIDs: Set<UUID>? = nil
    ) -> [MeetingRecord] {
        records.filter {
            $0.matchesSearch(searchText) || matchedRecordIDs?.contains($0.id) == true
        }
    }

    private var filteredRecords: [MeetingRecord] {
        Self.filteredRecords(
            from: app.meetingRecords,
            searchText: searchText,
            matchedRecordIDs: matchedRecordIDs
        )
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
                isSelected ? Color.jarvisAccent.opacity(0.14) : Color.clear,
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
    let isSearchEmpty: Bool

    var body: some View {
        Group {
            if let record {
                ScrollViewReader { proxy in
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
                                MeetingSummarySection(record: record, summary: summary) { segmentID in
                                    guard let segment = record.transcript.first(where: { $0.id == segmentID }) else {
                                        return
                                    }
                                    pendingSeekTime = segment.startTime
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        proxy.scrollTo(segment.id, anchor: .center)
                                    }
                                }
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
                }
            } else if isSearchEmpty {
                JarvisEmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的会议",
                    message: "试试会议名称、总结内容或逐字稿中的其他词语。"
                )
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
                        .tint(Color.jarvisAccent)
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
                    .foregroundStyle(Color.jarvisAccent)
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
    @Environment(AppModel.self) private var app
    @State private var isDiscussionExpanded = false
    @State private var isRegenerationConfirmationPresented = false
    let record: MeetingRecord
    let summary: MeetingSummary
    let onSeekToSegment: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MeetingSectionHeader(title: "会议总结", systemImage: "sparkles")
                Spacer()
                Button("重新生成") {
                    isRegenerationConfirmationPresented = true
                }
                .buttonStyle(.borderless)
                .disabled(app.meetingActiveProcessingID != nil)
                .accessibilityHint("根据当前逐字稿重新生成会议总结")
                if !summary.actionItems.isEmpty {
                    Text("\(summary.actionItems.filter { !$0.isCompleted }.count) 项待办")
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
            JarvisCard {
                VStack(alignment: .leading, spacing: 16) {
                    if !summary.overview.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("会议结论", systemImage: "checkmark.seal.fill")
                                .font(MeetingDetailTypography.h3)
                                .foregroundStyle(Color.jarvisAccent)
                                .accessibilityAddTraits(.isHeader)
                            Text(summary.overview)
                                .font(.system(size: 16, weight: .medium))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    actionList
                    summaryList(
                        title: "已确认决策",
                        icon: "checkmark.circle",
                        kind: .decision,
                        items: summary.decisions
                    )
                    summaryList(
                        title: "待确认问题",
                        icon: "questionmark.circle",
                        kind: .openQuestion,
                        items: summary.openQuestions
                    )
                    if !summary.keyPoints.isEmpty {
                        DisclosureGroup(isExpanded: $isDiscussionExpanded) {
                            summaryList(
                                title: "",
                                icon: "",
                                kind: .keyPoint,
                                items: summary.keyPoints,
                                showsHeading: false
                            )
                            .padding(.top, 8)
                        } label: {
                            Label("讨论要点（\(summary.keyPoints.count)）", systemImage: "text.alignleft")
                                .font(MeetingDetailTypography.h3)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "重新生成会议总结？",
            isPresented: $isRegenerationConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("重新生成") {
                app.summarizeMeeting(recordID: record.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将根据当前逐字稿覆盖现有总结。原始录音和逐字稿会保留。")
        }
    }

    @ViewBuilder
    private func summaryList(
        title: String,
        icon: String,
        kind: MeetingFactKind,
        items: [String],
        showsHeading: Bool = true
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if showsHeading {
                    Label(title, systemImage: icon)
                        .font(MeetingDetailTypography.h3)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.jarvisAccent)
                                .frame(width: 5, height: 5)
                                .padding(.top, 8)
                            Text(item)
                                .font(MeetingDetailTypography.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        sourceLinks(for: kind, text: item)
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
                    .accessibilityAddTraits(.isHeader)
                ForEach(summary.actionItems) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            app.setMeetingActionItemCompleted(
                                recordID: record.id,
                                actionItemID: item.id,
                                isCompleted: !item.isCompleted
                            )
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(item.isCompleted ? Color.jarvisAccent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.isCompleted ? "标记待办为未完成" : "标记待办为已完成：\(item.task)")

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.task)
                                .font(MeetingDetailTypography.body)
                                .strikethrough(item.isCompleted)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                Text("负责人：\(item.owner.isEmpty ? "未指定" : item.owner)")
                                Text("截止：\(item.dueDate.isEmpty ? "未指定" : item.dueDate)")
                            }
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                            sourceLinks(for: .actionItem, text: item.task)
                        }
                    }
                    .padding(.vertical, 7)
                    if item.id != summary.actionItems.last?.id {
                        Divider().opacity(0.55)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceLinks(for kind: MeetingFactKind, text: String) -> some View {
        let citations = (summary.citations ?? []).filter { $0.kind == kind && $0.text == text }
        if let citation = citations.first {
            HStack(spacing: 8) {
                ForEach(Array(citation.sourceSegmentIDs.prefix(2)), id: \.self) { segmentID in
                    if let segment = record.transcript.first(where: { $0.id == segmentID }) {
                        Button {
                            onSeekToSegment(segmentID)
                        } label: {
                            Label(
                                "原文 \(formatMeetingTimestamp(segment.startTime))",
                                systemImage: "arrow.uturn.down"
                            )
                        }
                        .buttonStyle(.plain)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisAccent)
                        .accessibilityHint("跳到对应逐字稿并播放录音")
                    }
                }
                if citation.sourceSegmentIDs.count > 2 {
                    Text("+\(citation.sourceSegmentIDs.count - 2) 处")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
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
                    .accessibilityLabel(
                        "\(speaker?.name ?? segment.speakerID)，"
                            + "\(formatMeetingTimestamp(segment.startTime))，\(segment.text)"
                    )
                    .accessibilityHint("双击从这段逐字稿开始播放录音")
                    .id(segment.id)
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

@MainActor
private func speakerColor(_ index: Int) -> Color {
    [Color.jarvisAccent, .purple, .orange, .green, .pink, .indigo][index % 6]
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
