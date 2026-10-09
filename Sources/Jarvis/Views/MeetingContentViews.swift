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
    @State private var highlightedSegmentID: UUID?
    @State private var isTranscriptExpanded = false

    var body: some View {
        JarvisContentArea(
            leadingToolbar: {
                ToolbarItem(id: "meeting.recording", placement: .navigation) {
                    recordingToolbarButton
                }
                ToolbarItem(id: "meeting.captureMode", placement: .navigation) {
                    captureModeToolbar
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
                    if !app.meetingRecords.isEmpty, !app.meetingModelsReady {
                        MeetingModelDownloadPrompt()
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 12)
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
                                    highlightedSegmentID: $highlightedSegmentID,
                                    isTranscriptExpanded: $isTranscriptExpanded,
                                    record: selectedRecord,
                                    isSearchEmpty: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        && filteredRecords.isEmpty,
                                    onToggleCitation: toggleCitation
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
        .confirmationDialog(
            "把逐字稿发给 AI 服务？",
            isPresented: Binding(
                get: { app.meetingTranscriptConsentRecordID != nil },
                set: { isPresented in
                    if !isPresented {
                        app.cancelMeetingTranscriptConsent()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("发送文本并生成") {
                app.confirmMeetingTranscriptConsent()
            }
            Button("取消", role: .cancel) {
                app.cancelMeetingTranscriptConsent()
            }
        } message: {
            Text(transcriptConsentMessage)
        }
        .onChange(of: app.selectedMeetingID) { _, newValue in
            pendingSeekTime = nil
            citedPlayback = CitedAudioPlayback()
            highlightedSegmentID = nil
            isTranscriptExpanded = false
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

    private func toggleCitation(at time: TimeInterval, segmentID: UUID?) {
        highlightedSegmentID = segmentID
        if segmentID != nil {
            isTranscriptExpanded = true
        }
        if citedPlayback.isPlaying, citedPlayback.activeTime == time {
            citedPlayback.stopRequest += 1
        } else {
            citedPlayback.activeTime = time
            pendingSeekTime = time
        }
    }

    private var transcriptConsentMessage: String {
        let provider = app.apiProvider.title
        let model = app.providerModel.isEmpty ? "当前模型" : app.providerModel
        return "生成纪要只会把这份会议的逐字稿文本发给设置中的 \(provider)（\(model)）。录音留在这台 Mac 上，不会发送。"
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

    private var captureModeToolbar: some View {
        let isRecording = app.meetingCurrentRecordingID != nil
        let activeMode = selectedRecord?.id == app.meetingCurrentRecordingID
            ? selectedRecord?.resolvedCaptureMode ?? app.meetingCaptureMode
            : app.meetingCaptureMode
        return Menu {
            ForEach(MeetingCaptureMode.allCases) { mode in
                Button {
                    app.setMeetingCaptureMode(mode)
                } label: {
                    if mode == app.meetingCaptureMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            Text(isRecording ? activeMode.title : app.meetingCaptureMode.title)
                .font(JarvisTypography.control)
        }
        .disabled(isRecording)
        .accessibilityLabel("录音方式")
        .accessibilityValue(isRecording ? activeMode.title : app.meetingCaptureMode.title)
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
                Text("录音留在本机。系统中文转写和说话人分段也在本机完成，只有生成纪要时才发送逐字稿文本。")
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
                    Text("开始前需要准备识别资源")
                        .font(JarvisTypography.bodyEmphasis)
                }
                Text("说话人识别模型由贾维斯下载一次。中文转写使用系统语音资源，由系统下载，之后可离线使用。应用不内置转写模型。资源没准备好时不能开始正式录音。")
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
                    if app.meetingModelDownloadTotalBytes > 0 || app.meetingModelDownloadCompletedBytes > 0 {
                        Text(downloadByteText)
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    HStack(spacing: 8) {
                        Button("取消下载") {
                            app.cancelMeetingModelPreparation()
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                        Button("稍后准备") {
                            app.postponeMeetingAssetDownload()
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("下载识别模型") {
                            app.prepareMeetingModels()
                        }
                        .buttonStyle(JarvisPrimaryButtonStyle())
                        Button("稍后准备") {
                            app.postponeMeetingAssetDownload()
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: 520)
    }

    private var downloadByteText: String {
        let completed = ByteCountFormatter.string(
            fromByteCount: app.meetingModelDownloadCompletedBytes,
            countStyle: .file
        )
        guard app.meetingModelDownloadTotalBytes > 0 else { return "已下载 \(completed)" }
        let total = ByteCountFormatter.string(
            fromByteCount: app.meetingModelDownloadTotalBytes,
            countStyle: .file
        )
        return "\(completed) / \(total)"
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
                Button("导出纪要 Markdown…") {
                    app.exportMeetingMarkdown(record, includeTranscript: true)
                }
                Button("导出逐字稿…") {
                    app.exportMeetingPlainTranscript(record)
                }
                Button("导出 PDF…") {
                    app.exportMeetingPDF(record)
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
        .sorted { lhs, rhs in
            (lhs.interruptedRecording == true) && rhs.interruptedRecording != true
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
            Text("将同时删除本机保存的原始录音、逐字稿和纪要，且无法恢复。")
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
                    if record.awaitingAssets == true {
                        Text("等待识别资源")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    } else if record.interruptedRecording == true {
                        Text("可恢复 · 已保留 \(formatMeetingDuration(record.duration)) · 不会自动转写")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(.orange)
                    }
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
    @Binding var highlightedSegmentID: UUID?
    @Binding var isTranscriptExpanded: Bool
    let record: MeetingRecord?
    let isSearchEmpty: Bool
    let onToggleCitation: (TimeInterval, UUID?) -> Void

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

                        if let reason = record.diarizationDegradeReason?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                            !reason.isEmpty
                        {
                            MeetingStorageErrorBanner(message: reason)
                        } else if record.diarizationDegraded == true {
                            MeetingStorageErrorBanner(
                                message: "说话人分离没有完成，逐字稿先不标说话人。纪要仍可生成。"
                            )
                        }

                        if let summary = record.summary {
                            MeetingSummarySection(
                                record: record,
                                summary: summary,
                                citedPlayback: citedPlayback,
                                onToggleCitation: onToggleCitation
                            )
                        } else if !record.transcript.isEmpty,
                                  record.status != .summarizing,
                                  record.status != .failed,
                                  record.status != .summaryFailed
                        {
                            MeetingNeedsSummaryCard(record: record)
                        }

                        if !record.transcript.isEmpty {
                            MeetingTranscriptSection(
                                record: record,
                                highlightedSegmentID: highlightedSegmentID,
                                isExpanded: $isTranscriptExpanded,
                                onPlay: onToggleCitation
                            )
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
                MeetingRecordingCard()
            } else {
                MeetingAudioPlayer(
                    audioURL: app.meetingAudioURL(for: record),
                    pendingSeekTime: $pendingSeekTime,
                    citedPlayback: $citedPlayback
                )
            }

            if !record.audioEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(record.audioEvents) { event in
                        Text(event.message)
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                }
            }
        }
    }
}

private struct MeetingTranscriptSection: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord
    let highlightedSegmentID: UUID?
    @Binding var isExpanded: Bool
    let onPlay: (TimeInterval, UUID?) -> Void
    @State private var speakerDrafts: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if record.estimatedSpeakerCount != nil || !record.speakerTurns.isEmpty {
                HStack(spacing: 12) {
                    if let count = record.estimatedSpeakerCount {
                        let percent = Int(((record.uncertainSegmentRatio ?? 0) * 100).rounded())
                        Text("预计 \(count) 位说话人，不确定片段 \(percent)%")
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    Spacer(minLength: 8)
                    if !record.speakerTurns.isEmpty {
                        Button("按已保存时段重新合并") {
                            app.remergeMeetingSpeakers(recordID: record.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            DisclosureGroup(isExpanded: $isExpanded) {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(record.transcript) { segment in
                            transcriptRow(segment)
                                .id(segment.id)
                        }
                    }
                    .padding(.top, 6)
                    .onChange(of: highlightedSegmentID) { _, segmentID in
                        guard let segmentID else { return }
                        withAnimation {
                            proxy.scrollTo(segmentID, anchor: .center)
                        }
                    }
                }
            } label: {
                MeetingSectionHeader(
                    title: "逐字稿（\(record.transcript.count)）",
                    systemImage: "text.quote"
                )
            }
        }
    }

    private func transcriptRow(_ segment: MeetingTranscriptSegment) -> some View {
        let speakerName = record.speakers.first { $0.id == segment.speakerID }?.name ?? segment.speakerID
        let isHighlighted = highlightedSegmentID == segment.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(formatMeetingTimestamp(segment.startTime))
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .frame(width: 52, alignment: .leading)
                TextField(
                    "说话人",
                    text: speakerNameBinding(speakerID: segment.speakerID, current: speakerName)
                )
                .textFieldStyle(.plain)
                .font(JarvisTypography.captionEmphasis)
                .frame(maxWidth: 140, alignment: .leading)
                .onSubmit {
                    app.renameMeetingSpeaker(
                        recordID: record.id,
                        speakerID: segment.speakerID,
                        name: speakerDrafts[segment.speakerID] ?? speakerName
                    )
                }
                Menu("改分段") {
                    ForEach(record.speakers) { speaker in
                        Button(speaker.name) {
                            app.reassignMeetingSegment(
                                recordID: record.id,
                                segmentID: segment.id,
                                speakerID: speaker.id
                            )
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button {
                    onPlay(segment.startTime, segment.id)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("播放这一段")
            }
            Text(segment.text)
                .font(MeetingDetailTypography.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
                .background(
                    isHighlighted ? Color.jarvisAccent.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }

    private func speakerNameBinding(speakerID: String, current: String) -> Binding<String> {
        Binding(
            get: { speakerDrafts[speakerID] ?? current },
            set: { speakerDrafts[speakerID] = $0 }
        )
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

private struct MeetingRecordingCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: app.meetingRecordingPaused ? "pause.fill" : "mic.fill")
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.meetingRecordingPaused ? "录音已暂停" : "正在录音")
                            .font(JarvisTypography.bodyEmphasis)
                        Text(statusLine)
                            .font(JarvisTypography.caption)
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }

                    Spacer(minLength: 12)
                    Text(formatMeetingDuration(app.meetingElapsed))
                        .font(JarvisTypography.monospaced)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    Button(app.meetingRecordingPaused ? "继续" : "暂停") {
                        if app.meetingRecordingPaused {
                            app.resumeMeetingRecording()
                        } else {
                            app.pauseMeetingRecording()
                        }
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                }

                VStack(alignment: .leading, spacing: 6) {
                    labeledMeter("麦克风", level: meterLevel(app.meetingMicrophonePower))
                    if activeCaptureMode == .dual {
                        labeledMeter("系统音频", level: meterLevel(app.meetingSystemPower))
                    }
                    Text("已写入 \(byteText)")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
        }
    }

    private var activeCaptureMode: MeetingCaptureMode {
        app.meetingRecords.first { $0.id == app.meetingCurrentRecordingID }?.resolvedCaptureMode
            ?? app.meetingCaptureMode
    }

    private var statusLine: String {
        switch activeCaptureMode {
        case .microphone:
            "线下单麦。房间里的声音都会写入麦克风。"
        case .dual:
            "线上双轨。麦克风只在你说话时写入。\(systemTrackText)"
        }
    }

    private var systemTrackText: String {
        guard let power = app.meetingSystemPower else { return "系统音轨还没有声音。" }
        return power < -45 ? "系统音轨当前没有声音。" : "系统音轨有声音。"
    }

    private var byteText: String {
        ByteCountFormatter.string(fromByteCount: app.meetingBytesWritten, countStyle: .file)
    }

    private func meterLevel(_ power: Float?) -> Double {
        guard let power else { return 0 }
        let clamped = min(0, max(-60, power))
        return Double((clamped + 60) / 60)
    }

    private func labeledMeter(_ title: String, level: Double) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
                .frame(width: 64, alignment: .leading)
            ProgressView(value: level)
                .tint(Color.jarvisAccent)
        }
        .accessibilityLabel(title)
        .accessibilityValue("\(Int((level * 100).rounded()))%")
    }
}

private struct MeetingAudioPlayer: View {
    let audioURL: URL?
    @Binding var pendingSeekTime: TimeInterval?
    @Binding var citedPlayback: CitedAudioPlayback
    @StateObject private var controller = MeetingAudioPlaybackController()
    private let playbackTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        JarvisCard {
            if controller.isAvailable {
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
            controller.load(url: audioURL)
        }
        .onChange(of: audioURL) { _, newValue in
            controller.load(url: newValue)
        }
        .onChange(of: pendingSeekTime) { _, newValue in
            guard let newValue else { return }
            controller.seek(to: newValue)
            if !controller.isPlaying {
                controller.togglePlayback()
            }
            citedPlayback.activeTime = newValue
            citedPlayback.isPlaying = controller.isPlaying
            pendingSeekTime = nil
        }
        .onChange(of: citedPlayback.stopRequest) { _, _ in
            controller.haltPlayback()
            citedPlayback.isPlaying = false
        }
        .onReceive(playbackTimer) { _ in
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
                    Text(failureTitle)
                        .font(JarvisTypography.bodyEmphasis)
                    Text(message)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if record.awaitingAssets == true {
                    Button("开始录音") {
                        app.selectedMeetingID = record.id
                        Task { await app.startMeetingRecording(reusing: record.id) }
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                    .disabled(!app.meetingModelsReady || app.meetingCurrentRecordingID != nil)
                } else if record.canRetryProcessing {
                    Button(record.status == .summaryFailed ? "重新生成纪要" : "重新处理") {
                        app.selectedMeetingID = record.id
                        app.retryMeetingProcessing(record)
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                }
            }
        }
    }

    private var failureTitle: String {
        if record.awaitingAssets == true {
            return "等待识别资源"
        }
        if record.status == .summaryFailed {
            return "会议纪要生成失败"
        }
        return "处理失败"
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
    @State private var isRegenerationConfirmationPresented = false
    @State private var overviewDraft = ""
    @FocusState private var isOverviewFocused: Bool
    let record: MeetingRecord
    let summary: MeetingSummary
    let citedPlayback: CitedAudioPlayback
    let onToggleCitation: (TimeInterval, UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MeetingSectionHeader(title: "会议纪要", systemImage: "sparkles")
                Spacer()
                Button("重新生成") {
                    isRegenerationConfirmationPresented = true
                }
                .buttonStyle(.borderless)
                .disabled(app.meetingActiveProcessingID != nil)
                .accessibilityHint("根据当前逐字稿重新生成会议纪要")
            }
            JarvisCard {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("概要", systemImage: "text.alignleft")
                            .font(MeetingDetailTypography.h3)
                            .foregroundStyle(Color.jarvisAccent)
                            .accessibilityAddTraits(.isHeader)
                        TextField("概要", text: $overviewDraft, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .medium))
                            .focused($isOverviewFocused)
                            .onChange(of: isOverviewFocused) { _, isFocused in
                                if !isFocused {
                                    commitOverview()
                                }
                            }
                    }
                    if !summary.renderedPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("讨论要点", systemImage: "list.bullet")
                                .font(MeetingDetailTypography.h3)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(summary.renderedPoints) { point in
                                pointRow(point)
                            }
                        }
                    }
                }
            }
            if !record.minutesVersions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("较早的纪要")
                        .font(JarvisTypography.captionEmphasis)
                        .foregroundStyle(Color.jarvisTextSecondary)
                    ForEach(record.minutesVersions) { version in
                        HStack(spacing: 8) {
                            Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(JarvisTypography.caption)
                                .foregroundStyle(Color.jarvisTextSecondary)
                            Text(version.summary.overview)
                                .font(JarvisTypography.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Button("恢复此版本") {
                                app.restoreMeetingMinutesVersion(recordID: record.id, versionID: version.id)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .onAppear {
            overviewDraft = summary.overview
        }
        .onChange(of: summary.overview) { _, newValue in
            if !isOverviewFocused {
                overviewDraft = newValue
            }
        }
        .confirmationDialog(
            "重新生成会议纪要？",
            isPresented: $isRegenerationConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("合并到当前纪要") {
                app.summarizeMeeting(recordID: record.id, preserveUserEdits: true)
            }
            Button("另存为新版本") {
                app.summarizeMeeting(recordID: record.id, preserveUserEdits: false)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("合并到当前纪要会保留你改过的概要、讨论要点、待办，以及已勾选的待办。另存为新版本会把当前纪要收进版本列表，再生成一份新的。原始录音和逐字稿都会保留。")
        }
    }

    private func commitOverview() {
        let trimmed = overviewDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != summary.overview else { return }
        app.updateMeetingOverview(recordID: record.id, overview: trimmed)
    }

    private func pointRow(_ point: MeetingDiscussionPoint) -> some View {
        let target = meetingEvidenceTarget(evidence: point.evidence, record: record)
        let text = point.detail.isEmpty ? point.title : "\(point.title)\n\(point.detail)"
        return HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.jarvisAccent)
                .frame(width: 5, height: 5)
                .padding(.top, 8)
            MeetingCitedSentence(
                text: text,
                playTime: target?.time,
                isPlaying: target.map { citedPlayback.isPlayingCitation($0.time) } ?? false,
                onToggle: { time in
                    onToggleCitation(time, target?.segmentID)
                }
            )
        }
    }
}

private struct MeetingActionItemsPanel: View {
    @Environment(AppModel.self) private var app
    let record: MeetingRecord?
    let citedPlayback: CitedAudioPlayback
    let onToggleCitation: (TimeInterval, UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("待办")
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
                let target = meetingActionTarget(item: item, record: record, summary: summary)
                MeetingCitedSentence(
                    text: item.task,
                    isStrikethrough: item.isCompleted,
                    playTime: target?.time,
                    isPlaying: target.map { citedPlayback.isPlayingCitation($0.time) } ?? false,
                    onToggle: { time in
                        onToggleCitation(time, target?.segmentID)
                    }
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("负责人：\(item.ownerLabel)")
                    Text("期限：\(item.dueLabel)")
                }
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.jarvisTextSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct MeetingPlayTarget {
    var time: TimeInterval
    var segmentID: UUID?
}

private func meetingEvidenceTarget(
    evidence: [MeetingEvidence],
    record: MeetingRecord
) -> MeetingPlayTarget? {
    guard let first = evidence.first else { return nil }
    let segment = record.transcript.first { $0.id == first.segmentID }
    let time = first.startMs > 0 ? Double(first.startMs) / 1000 : segment?.startTime
    guard let time else { return nil }
    return MeetingPlayTarget(time: time, segmentID: segment?.id ?? first.segmentID)
}

private func meetingActionTarget(
    item: MeetingActionItem,
    record: MeetingRecord,
    summary: MeetingSummary
) -> MeetingPlayTarget? {
    if let target = meetingEvidenceTarget(evidence: item.evidence, record: record) {
        return target
    }
    guard let citation = summary.citations?.first(where: { $0.kind == .actionItem && $0.text == item.task }),
          let segmentID = citation.sourceSegmentIDs.first,
          let segment = record.transcript.first(where: { $0.id == segmentID })
    else { return nil }
    return MeetingPlayTarget(time: segment.startTime, segmentID: segment.id)
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
