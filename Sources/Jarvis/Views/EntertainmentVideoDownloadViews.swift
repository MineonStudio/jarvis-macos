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
            urlBar
                .padding(.bottom, 12)

            if isAnalyzing {
                analyzingState
            } else if let analyzeError {
                errorState(analyzeError)
            } else if let probe {
                probeCard(probe)
            }

            Divider()
                .padding(.vertical, 12)

            taskList

            Divider()
                .padding(.top, 12)

            Button {
                manager.openDownloadsFolder()
            } label: {
                Label("打开下载文件夹", systemImage: "folder")
                    .font(JarvisTypography.control)
            }
            .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
            .foregroundStyle(Color.accentColor)
            .padding(.top, 10)
        }
        .padding(16)
        .onAppear(perform: prefillURL)
        .onChange(of: initialURL) { _, _ in
            if urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefillURL()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("视频下载")
                .font(JarvisTypography.cardTitle)
            Spacer()
            if manager.hasDownloads {
                Button("清理已完成") {
                    manager.clearFinished()
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                .foregroundStyle(Color.accentColor)
                .font(JarvisTypography.control)
            }
        }
        .padding(.bottom, 12)
    }

    private var urlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("粘贴 YouTube / X / TikTok 链接", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(JarvisTypography.control)
                Button("粘贴") {
                    pasteFromClipboard()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
                Button("解析") {
                    Task { await analyze() }
                }
                .buttonStyle(JarvisPrimaryButtonStyle())
                .disabled(isAnalyzing || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("复制视频链接后点粘贴，选择分辨率再下载")
                .font(JarvisTypography.caption)
                .foregroundStyle(Color.secondary)
        }
    }

    private var analyzingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在解析视频信息和可用分辨率…")
                .font(JarvisTypography.secondary)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private func errorState(_ message: String) -> some View {
        Text(message)
            .font(JarvisTypography.secondary)
            .foregroundStyle(Color.red)
            .padding(.bottom, 8)
    }

    private func probeCard(_ probe: EntertainmentVideoProbe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                thumbnail(probe.thumbnailURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(probe.title)
                        .font(JarvisTypography.bodyEmphasis)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(probe.platform.title)
                        if let duration = probe.duration {
                            Text(Self.formatDuration(duration))
                        }
                    }
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                ForEach(probe.qualities) { quality in
                    qualityRow(quality)
                }
            }

            Button {
                downloadSelected(from: probe)
            } label: {
                Text("下载所选分辨率")
                    .font(JarvisTypography.controlEmphasis)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedQuality(from: probe) == nil)
        }
        .padding(.bottom, 4)
    }

    private func qualityRow(_ quality: EntertainmentVideoQuality) -> some View {
        let isSelected = selectedQualityID == quality.id
        return Button {
            selectedQualityID = quality.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(quality.title)
                        .font(JarvisTypography.controlEmphasis)
                    Text(quality.subtitle)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.jarvisPanel.opacity(0.72))
            )
        }
        .buttonStyle(.plain)
    }

    private var taskList: some View {
        Group {
            if manager.items.isEmpty {
                Text("解析链接并选择分辨率后开始下载")
                    .font(JarvisTypography.secondary)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.items) { item in
                            EntertainmentVideoDownloadRow(item: item, manager: manager)
                        }
                    }
                }
                .frame(minHeight: 88, maxHeight: 160)
            }
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: manager.items.count
        )
    }

    private func thumbnail(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.jarvisPanel)
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(Color.secondary)
                }
        }
        .frame(width: 88, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func prefillURL() {
        if let initialURL, EntertainmentVideoLink.platform(for: initialURL) != nil {
            urlText = initialURL.absoluteString
            return
        }
        if let clipboard = NSPasteboard.general.string(forType: .string),
           EntertainmentVideoLink.match(clipboard) != nil
        {
            urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func pasteFromClipboard() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else { return }
        urlText = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.state.icon)
                .foregroundStyle(stateColor)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(JarvisTypography.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(item.platform.title) · \(item.qualityTitle) · \(item.state.title)")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.secondary)
                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(JarvisTypography.caption)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
                if item.state == .downloading {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }
            }

            Spacer(minLength: 4)

            if item.state.isActive {
                Button("取消") {
                    manager.cancel(item)
                }
                .buttonStyle(JarvisPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.84))
                .font(JarvisTypography.captionEmphasis)
                .foregroundStyle(Color.secondary)
            } else if item.canOpenFile {
                Menu {
                    Button("打开文件") {
                        manager.open(item)
                    }
                    Button("在 Finder 中显示") {
                        manager.revealInFinder(item)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.secondary)
                }
                .menuStyle(.borderlessButton)
            }
        }
        .padding(10)
        .background(Color.jarvisPanel.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
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
