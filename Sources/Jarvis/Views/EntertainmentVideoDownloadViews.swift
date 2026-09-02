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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("下载")
                    .font(JarvisTypography.cardTitle)
                Spacer()
                Button {
                    manager.openDownloadsFolder()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help("打开下载文件夹")
            }

            HStack(spacing: 8) {
                TextField("粘贴视频链接", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                Button("粘贴") {
                    pasteFromClipboard()
                }
                .buttonStyle(JarvisSecondaryButtonStyle())
            }

            HStack(spacing: 8) {
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text("解析中")
                        .font(JarvisTypography.secondary)
                        .foregroundStyle(Color.secondary)
                } else {
                    Button("解析") {
                        Task { await analyze() }
                    }
                    .buttonStyle(JarvisPrimaryButtonStyle())
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
            }

            if let analyzeError {
                Text(analyzeError)
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let probe {
                VStack(alignment: .leading, spacing: 8) {
                    Text(probe.title)
                        .font(JarvisTypography.bodyEmphasis)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Picker("画质", selection: qualityBinding(for: probe)) {
                            ForEach(probe.qualities) { quality in
                                Text(quality.title).tag(quality.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 88)

                        Button("下载") {
                            downloadSelected(from: probe)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedQuality(from: probe) == nil)
                    }
                }
            }

            if !manager.items.isEmpty {
                Divider()
                VStack(spacing: 6) {
                    ForEach(manager.items.prefix(5)) { item in
                        EntertainmentVideoDownloadRow(item: item, manager: manager)
                    }
                }
            }
        }
        .padding(14)
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: manager.items.count
        )
        .onAppear {
            prefillURL()
            if EntertainmentVideoLink.match(urlText) != nil {
                Task { await analyze() }
            }
        }
    }

    private func qualityBinding(for probe: EntertainmentVideoProbe) -> Binding<String> {
        Binding(
            get: { selectedQualityID ?? preferredQualityID(in: probe.qualities) ?? "" },
            set: { selectedQualityID = $0 }
        )
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
                Button("打开") { manager.open(item) }
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
