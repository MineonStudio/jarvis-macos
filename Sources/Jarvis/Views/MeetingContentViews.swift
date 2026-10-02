import AVFoundation
import Combine
import SwiftUI

private enum MeetingDetailTypography {
    static let h1 = Font.system(size: 26, weight: .semibold, design: .rounded)
    static let h2 = Font.system(size: 20, weight: .semibold)
    static let h3 = Font.system(size: 16, weight: .semibold)
    static let body = Font.system(size: 15)
}

private enum MeetingPaneMetrics {
    static let sideColumnWidth: CGFloat = 246
}

struct MeetingView: View {
    @Environment(AppModel.self) private var app
    @State private var searchText = ""
    @State private var searchMatchedRecordIDs: Set<UUID>?
    @State private var pendingSeekTime: TimeInterval?
    @State private var citedPlayback = CitedAudioPlayback()

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
                                .frame(width: MeetingPaneMetrics.sideColumnWidth)
                                .frame(maxHeight: .infinity)
                                .jarvisModulePanel()

                                MeetingDetailPane(
                                    pendingSeekTime: $pendingSeekTime,
                                    citedPlayback: $citedPlayback,
                                    record: selectedRecord,
                                    isSearchEmpty: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        && filteredRecords.isEmpty
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .jarvisModulePanel()

                                MeetingActionItemsPanel(
                                    record: selectedRecord,
                                    citedPlayback: citedPlayback,
                                    onToggleCitation: toggleCitation
                                )
                                .frame(width: MeetingPaneMetrics.sideColumnWidth)
                                .frame(maxHeight: .infinity)
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
            pendingSeekTime = nil
            citedPlayback = CitedAudioPlayback()
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

    private func toggleCitation(at time: TimeInterval) {
        if citedPlayback.isPlaying, citedPlayback.activeTime == time {
            citedPlayback.stopRequest += 1
        } else {
            citedPlayback.activeTime = time
            pendingSeekTime = time
        }
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
    @Binding var pendingSeekTime: TimeInterval?
    @Binding var citedPlayback: CitedAudioPlayback
    let record: MeetingRecord?
    let isSearchEmpty: Bool

    var body: some View {
        Group {
            if let record {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        meetingHeader(record)

                        MeetingAudioSection(
                            record: record,
                            pendingSeekTime: $pendingSeekTime,
                            citedPlayback: $citedPlayback
                        )

                        if shouldShowProgress(for: record) {
                            MeetingProcessingCard(state: app.meetingProcessingState)
                        }

                        if record.status == .failed || record.status == .summaryFailed,
                           let errorMessage = record.errorMessage
                        {
                            MeetingFailureCard(record: record, message: errorMessage)
                        }

                        if let summary = record.summary {
                            MeetingSummarySection(
                                record: record,
                                summary: summary,
                                citedPlayback: citedPlayback,
                                onToggleCitation: toggleCitation
                            )
                        } else if !record.transcript.isEmpty,
                                  record.status != .summarizing,
                                  record.status != .failed,
                                  record.status != .summaryFailed
                        {
                            MeetingNeedsSummaryCard(record: record)
                        }

                        // 改进 #3：逐字稿以前在详情页根本没地方看（只能被搜索到）。
                        // 默认折叠，展开后按时间列出每一段；只读展示，不做跳转交互。
                        if !record.transcript.isEmpty {
                            MeetingTranscriptSection(record: record)
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(JarvisMetrics.pageInset)
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

    private func toggleCitation(at time: TimeInterval) {
        if citedPlayback.isPlaying, citedPlayback.activeTime == time {
            citedPlayback.stopRequest += 1
        } else {
            citedPlayback.activeTime = time
            pendingSeekTime = time
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
    @Binding var citedPlayback: CitedAudioPlayback

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
                    pendingSeekTime: $pendingSeekTime,
                    citedPlayback: $citedPlayback
                )
            } else {
                MeetingAudioPlayer(
                    title: "原始录音",
                    audioURL: app.meetingAudioURL(for: record),
                    isRecording: false,
                    recordingElapsed: 0,
                    pendingSeekTime: $pendingSeekTime,
                    citedPlayback: $citedPlayback
                )
            }
        }
    }
}

/// 改进 #3：默认折叠的逐字稿区。只读展示，展开后按时间列出每一段。
private struct MeetingTranscriptSection: View {
    @State private var isExpanded = false
    let record: MeetingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $isExpanded) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(record.transcript) { segment in
                        HStack(alignment: .top, spacing: 10) {
                            Text(formatMeetingTimestamp(segment.startTime))
                                .font(JarvisTypography.caption)
                                .foregroundStyle(Color.jarvisTextSecondary)
                                .frame(width: 44, alignment: .leading)
                            Text(segment.text)
                                .font(MeetingDetailTypography.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                MeetingSectionHeader(
                    title: "逐字稿（\(record.transcript.count)）",
                    systemImage: "text.quote"
                )
            }
        }
    }
}

private struct CitedAudioPlayback: Equatable {
    var activeTime: TimeInterval?
    var isPlaying = false
    var stopRequest = 0

    func isPlayingCitation(_ time: TimeInterval) -> Bool {
        isPlaying && activeTime == time
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

    func haltPlayback() {
        audioPlayer?.stop()
        currentTime = audioPlayer?.currentTime ?? 0
        isPlaying = false
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
    @Binding var citedPlayback: CitedAudioPlayback
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
                            citedPlayback.isPlaying = controller.isPlaying
                        } label: {
                            Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(JarvisPrimaryButtonStyle())
                        .accessibilityLabel(controller.isPlaying ? "暂停原始录音" : "播放原始录音")

                        Slider(
                            value: Binding(
                                get: { controller.currentTime },
                                set: { newValue in
                                    controller.seek(to: newValue)
                                    citedPlayback.activeTime = nil
                                }
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
            citedPlayback.activeTime = newValue
            citedPlayback.isPlaying = controller.isPlaying
            pendingSeekTime = nil
        }
        .onChange(of: citedPlayback.stopRequest) { _, _ in
            guard !isRecording else { return }
            controller.haltPlayback()
            citedPlayback.isPlaying = false
        }
        .onReceive(playbackTimer) { _ in
            guard !isRecording else { return }
            controller.refreshAvailability()
            controller.refreshProgress()
            if citedPlayback.isPlaying != controller.isPlaying {
                citedPlayback.isPlaying = controller.isPlaying
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
                    if case let .processing(_, progress) = state, let progress {
                        Text("\(Int(progress * 100))%")
                            .font(JarvisTypography.monospaced)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
                if case let .processing(_, progress) = state {
                    if let progress {
                        ProgressView(value: progress)
                            .tint(Color.jarvisAccent)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(Color.jarvisAccent)
                    }
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
    let citedPlayback: CitedAudioPlayback
    let onToggleCitation: (TimeInterval) -> Void

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
                    let playTime = meetingSourcePlayTime(
                        record: record,
                        summary: summary,
                        kind: kind,
                        text: item
                    )
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.jarvisAccent)
                            .frame(width: 5, height: 5)
                            .padding(.top, 8)
                        MeetingCitedSentence(
                            text: item,
                            playTime: playTime,
                            isPlaying: playTime.map(citedPlayback.isPlayingCitation) ?? false,
                            onToggle: onToggleCitation
                        )
                    }
                }
            }
        }
    }
}

private struct MeetingActionItemsPanel: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord?
    let citedPlayback: CitedAudioPlayback
    let onToggleCitation: (TimeInterval) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待办事项")
                    .font(JarvisTypography.bodyEmphasis)
                Spacer()
                Text("\(actionItems.count)")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(Color.jarvisTextSecondary)
            }
            .padding(.horizontal, 10)
            .accessibilityAddTraits(.isHeader)

            if actionItems.isEmpty {
                Text(emptyMessage)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 10)
            } else if let record, let summary = record.summary {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(actionItems) { item in
                            actionRow(item, record: record, summary: summary)
                            if item.id != actionItems.last?.id {
                                Divider().opacity(0.55)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var actionItems: [MeetingActionItem] {
        record?.summary?.actionItems ?? []
    }

    private var emptyMessage: String {
        guard record != nil else { return "选择一条会议" }
        guard record?.summary != nil else { return "生成总结后，待办会显示在这里" }
        return "这次会议没有待办"
    }

    private func actionRow(
        _ item: MeetingActionItem,
        record: MeetingRecord,
        summary: MeetingSummary
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                app.setMeetingActionItemCompleted(
                    recordID: record.id,
                    actionItemID: item.id,
                    isCompleted: !item.isCompleted
                )
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? Color.jarvisAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "标记待办为未完成" : "标记待办为已完成：\(item.task)")

            VStack(alignment: .leading, spacing: 4) {
                let playTime = meetingSourcePlayTime(
                    record: record,
                    summary: summary,
                    kind: .actionItem,
                    text: item.task
                )
                MeetingCitedSentence(
                    text: item.task,
                    isStrikethrough: item.isCompleted,
                    playTime: playTime,
                    isPlaying: playTime.map(citedPlayback.isPlayingCitation) ?? false,
                    onToggle: onToggleCitation
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("负责人：\(item.owner.isEmpty ? "未指定" : item.owner)")
                    Text("截止：\(item.dueDate.isEmpty ? "未指定" : item.dueDate)")
                }
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private func meetingSourcePlayTime(
    record: MeetingRecord,
    summary: MeetingSummary,
    kind: MeetingFactKind,
    text: String
) -> TimeInterval? {
    guard let citation = summary.citations?.first(where: { $0.kind == kind && $0.text == text }) else {
        return nil
    }
    let times = citation.sourceSegmentIDs.compactMap { segmentID in
        record.transcript.first { $0.id == segmentID }?.startTime
    }
    return times.min()
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

private struct MeetingCitedSentence: View {
    let text: String
    var isStrikethrough = false
    var playTime: TimeInterval?
    var isPlaying = false
    let onToggle: (TimeInterval) -> Void

    var body: some View {
        if let playTime {
            Button {
                onToggle(playTime)
            } label: {
                citationText
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "停止播放" : "播放原文 \(formatMeetingTimestamp(playTime))")
            .accessibilityLabel(text)
            .accessibilityHint(isPlaying ? "停止播放" : "从对应位置播放录音")
        } else {
            Text(text)
                .font(MeetingDetailTypography.body)
                .foregroundStyle(Color.primary)
                .strikethrough(isStrikethrough)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var citationText: Text {
        let sentence = Text(text)
            .font(MeetingDetailTypography.body)
            .foregroundStyle(Color.primary)
            .strikethrough(isStrikethrough)
        let symbol = Text(Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.jarvisAccent)
            .baselineOffset(-1)
        return Text("\(sentence)\u{00A0}\(symbol)")
    }
}
