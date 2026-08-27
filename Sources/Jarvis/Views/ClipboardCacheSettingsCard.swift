import SwiftUI

struct ClipboardCacheSettingsCard: View {
    @EnvironmentObject private var app: AppModel

    private let megabyte: Double = 1024 * 1024

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("剪贴板缓存", systemImage: "externaldrive")
                    .font(.system(size: 14, weight: .semibold))

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("缓存文件夹")
                            .font(.system(size: 12, weight: .semibold))
                        Text(app.clipboardCacheDirectoryURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.jarvisTextSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button("更改文件夹") {
                        app.chooseClipboardCacheDirectory()
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                }

                Divider().overlay(Color.primary.opacity(0.12))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("缓存空间上限")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(byteDescription(app.clipboardCacheMaximumBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(app.clipboardCacheMaximumBytes) / megabyte },
                            set: { app.updateClipboardCacheMaximumBytes(Int64($0 * megabyte)) }
                        ),
                        in: Double(ClipboardCacheStore.minimumMaximumBytes) / megabyte ...
                            Double(ClipboardCacheStore.maximumMaximumBytes) / megabyte,
                        step: 256
                    )
                    HStack {
                        Text("256 MB")
                        Spacer()
                        Text("10 GB")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color.jarvisTextSecondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("当前占用")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(byteDescription(app.clipboardCacheUsage.usedBytes)) / \(byteDescription(app.clipboardCacheUsage.capacityBytes))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(app.clipboardCacheUsage.isOverCapacity ? .red : Color.jarvisTextSecondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.10))
                            Capsule()
                                .fill(app.clipboardCacheUsage.isOverCapacity ? Color.red : Color.accentColor)
                                .frame(width: proxy.size.width * app.clipboardCacheUsage.fraction)
                        }
                    }
                    .frame(height: 8)
                    Text("已保存 \(app.clipboardCacheUsage.fileCount) 个缓存文件")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }
            }
        }
        .onAppear {
            app.refreshClipboardCacheUsage()
        }
    }

    private func byteDescription(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: bytes)
    }
}
