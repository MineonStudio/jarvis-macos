import AppKit
import SwiftUI

struct EntertainmentVideoDownloadView: View {
    @ObservedObject var manager: EntertainmentVideoDownloadManager
    let initialURL: URL?
    @State private var urlText = ""
    @State private var isAnalyzing = false
    @State private var analyzeError: String?
    @State private var probe: EntertainmentVideoProbe?
    @State private var selectedQualityID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            inputSection
            if let analyzeError {
                Text(analyzeError)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            if let probe {
                probeSection(probe)
            }
            if !manager.activeItems.isEmpty {
                activeSection
            }
            historySection
            footer
        }
        .frame(width: 360)
        .frame(minHeight: 300, maxHeight: 460)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: manager.items.count
        )
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: manager.history.count
        )
        .onAppear {
            prefillURL()
            if EntertainmentVideoLink.match(urlText) != nil {
                Task { await analyze() }
            }
        }
        .onChange(of: initialURL) { _, _ in
            prefillURL()
            if EntertainmentVideoLink.match(urlText) != nil {
                Task { await analyze() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("视频下载")
                .font(JarvisTypography.cardTitle)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("粘贴视频链接", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(JarvisTypography.control)
                    .padding(.horizontal, 10)
                    .frame(height: JarvisToolbarMetrics.controlSize)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Button("粘贴") {
                    pasteFromClipboard()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: JarvisToolbarMetrics.controlSize)
                } else {
                    Button("解析") {
                        Task { await analyze() }
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func probeSection(_ probe: EntertainmentVideoProbe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(probe.title)
                .font(JarvisTypography.bodyEmphasis)
                .lineLimit(2)
            HStack(spacing: 8) {
                Picker("画质", selection: qualityBinding(for: probe)) {
                    ForEach(probe.qualities) { quality in
                        Text(quality.title).tag(quality.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("下载") {
                    downloadSelected(from: probe)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedQuality(from: probe) == nil)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("正在下载")
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.secondary)
            ForEach(manager.activeItems) { item in
                EntertainmentVideoDownloadRow(item: item, manager: manager)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("下载历史")
                    .font(JarvisTypography.captionEmphasis)
                    .foregroundStyle(Color.secondary)
                Spacer()
                if !manager.history.isEmpty {
                    Button("清除全部") {
                        manager.clearHistory()
                    }
                    .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.accentColor)
                    .help("清除所有下载历史")
                }
            }
            .padding(.horizontal, 16)

            if manager.history.isEmpty {
                Text("暂无下载历史")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.history) { record in
                            EntertainmentVideoHistoryRow(record: record, manager: manager)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                .frame(minHeight: 120, maxHeight: 220)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                manager.openDownloadsFolder()
            } label: {
                Label("打开下载文件夹", systemImage: "folder")
                    .font(JarvisTypography.control)
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func qualityBinding(for probe: EntertainmentVideoProbe) -> Binding<String> {
        Binding(
            get: { selectedQualityID ?? preferredQualityID(in: probe.qualities) ?? "" },
            set: { selectedQualityID = $0 }
        )
    }

    private func prefillURL() {
        if let sourceURL = EntertainmentVideoLink.preferredURL(
            initialURL: initialURL,
            clipboardText: NSPasteboard.general.string(forType: .string)
        ) {
            applyURLText(sourceURL.absoluteString)
        }
    }

    private func pasteFromClipboard() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
        if let matchedURL = EntertainmentVideoLink.match(clipboard)?.url {
            applyURLText(matchedURL.absoluteString)
        } else {
            applyURLText(clipboard.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func applyURLText(_ text: String) {
        guard urlText != text else { return }
        urlText = text
        probe = nil
        selectedQualityID = nil
        analyzeError = nil
    }

    private func analyze() async {
        isAnalyzing = true
        analyzeError = nil
        probe = nil
        defer { isAnalyzing = false }
        do {
            let result = try await manager.probe(urlText: urlText)
            probe = result
            selectedQualityID = preferredQualityID(in: result.qualities)
        } catch {
            analyzeError = error.localizedDescription
        }
    }

    private func downloadSelected(from probe: EntertainmentVideoProbe) {
        guard let quality = selectedQuality(from: probe) else { return }
        manager.download(probe: probe, quality: quality)
    }

    private func selectedQuality(from probe: EntertainmentVideoProbe) -> EntertainmentVideoQuality? {
        probe.qualities.first(where: { $0.id == selectedQualityID }) ?? probe.qualities.first
    }

    private func preferredQualityID(in qualities: [EntertainmentVideoQuality]) -> String? {
        qualities.first(where: { $0.height == 1080 })?.id
            ?? qualities.first(where: { $0.id == "best" })?.id
            ?? qualities.first?.id
    }

    static func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

private struct EntertainmentVideoDownloadRow: View {
    let item: EntertainmentVideoDownloadItem
    @ObservedObject var manager: EntertainmentVideoDownloadManager
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.state.icon)
                .foregroundStyle(stateColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(JarvisTypography.captionEmphasis)
                    .lineLimit(1)
                if item.state == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                } else {
                    Text("\(item.qualityTitle) · \(item.state.title)")
                        .font(JarvisTypography.caption)
                        .foregroundStyle(item.state == .failed ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if item.state.isActive {
                Button("取消") { manager.cancel(item) }
                    .font(JarvisTypography.caption)
                    .buttonStyle(.plain)
            } else if item.canOpenFile {
                Button(didCopy ? "已复制" : "复制") {
                    if manager.copyFile(item) {
                        didCopy = true
                    }
                }
                .font(JarvisTypography.caption)
                .buttonStyle(.plain)
                Button("下载") {
                    manager.saveCopy(item)
                }
                .font(JarvisTypography.caption)
                .buttonStyle(.plain)
            }
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .completed: .green
        case .failed: .red
        case .cancelled: .secondary
        case .queued, .downloading: .accentColor
        }
    }
}

private struct EntertainmentVideoHistoryRow: View {
    let record: EntertainmentVideoDownloadRecord
    @ObservedObject var manager: EntertainmentVideoDownloadManager
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: historyIcon)
                .foregroundStyle(historyColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(JarvisTypography.captionEmphasis)
                    .lineLimit(1)
                Text(subtitle)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(subtitleUsesErrorColor ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if record.canOpenFile {
                Button(didCopy ? "已复制" : "复制") {
                    if manager.copyFile(record) {
                        didCopy = true
                    }
                }
                .font(JarvisTypography.caption)
                .buttonStyle(.plain)
                Button("显示") { manager.revealInFinder(record) }
                    .font(JarvisTypography.caption)
                    .buttonStyle(.plain)
            }
            Button("删除") { manager.removeFromHistory(record) }
                .font(JarvisTypography.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help("从历史中删除")
        }
        .padding(.vertical, 4)
        .contextMenu {
            if record.canOpenFile {
                Button("复制文件") {
                    _ = manager.copyFile(record)
                }
                Button("在 Finder 中显示") { manager.revealInFinder(record) }
            }
            Button("删除记录", role: .destructive) {
                manager.removeFromHistory(record)
            }
        }
    }

    private var subtitleUsesErrorColor: Bool {
        record.state == .failed || (record.state == .completed && !record.fileExists)
    }

    private var subtitle: String {
        let stamp = EntertainmentVideoDownloadHistory.timestamp(record.finishedAt)
        if record.state == .completed, !record.fileExists {
            return "\(record.platform.title) · 文件已不存在 · \(stamp)"
        }
        if record.state == .failed {
            return "\(record.qualityTitle) · \(record.errorMessage ?? record.state.title) · \(stamp)"
        }
        return "\(record.platform.title) · \(record.qualityTitle) · \(record.state.title) · \(stamp)"
    }

    private var historyIcon: String {
        if record.state == .completed, !record.fileExists {
            return "questionmark.folder"
        }
        return record.state.icon
    }

    private var historyColor: Color {
        if record.state == .completed, !record.fileExists {
            return .secondary
        }
        switch record.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .queued, .downloading: return .accentColor
        }
    }
}
