import SwiftUI

struct ClipboardCacheSettingsCard: View {
    @EnvironmentObject private var app: AppModel

    private let capacityOptions = ClipboardCacheStore.supportedMaximumBytes

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
                        Text(capacityDescription(app.clipboardCacheMaximumBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.jarvisTextSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: {
                                let defaultIndex = capacityOptions.firstIndex(
                                    of: ClipboardCacheStore.defaultMaximumBytes
                                ) ?? 0
                                return Double(
                                    capacityOptions.firstIndex(of: app.clipboardCacheMaximumBytes)
                                        ?? defaultIndex
                                )
                            },
                            set: { index in
                                let optionIndex = min(
                                    max(Int(index.rounded()), 0),
                                    capacityOptions.count - 1
                                )
                                app.updateClipboardCacheMaximumBytes(capacityOptions[optionIndex])
                            }
                        ),
                        in: 0 ... Double(capacityOptions.count - 1),
                        step: 1
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("当前占用")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text("\(byteDescription(app.clipboardCacheUsage.usedBytes)) / \(capacityDescription(app.clipboardCacheUsage.capacityBytes))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    GeometryReader { proxy in
                        let usage = app.clipboardCacheUsage
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.10))
                            Capsule()
                                .fill(usageColor(for: usage))
                                .frame(
                                    width: proxy.size.width * usage.fraction,
                                    height: proxy.size.height
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 8)
                    Text("已保存 \(app.clipboardCacheUsage.fileCount) 个缓存文件")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)
                }

                Divider().overlay(Color.primary.opacity(0.12))

                VStack(alignment: .leading, spacing: 10) {
                    Text("清理缓存")
                        .font(.system(size: 14, weight: .semibold))
                    Text("所有清理均不包含已收藏内容")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)

                    Text("按分类清理")
                        .font(.system(size: 12, weight: .semibold))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 90), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach([
                            ClipboardCacheCategory.image,
                            .video,
                            .file,
                            .all
                        ]) { category in
                            cleanupButton(category.title) {
                                app.clearClipboardCache(category: category)
                            }
                        }
                    }

                    Text("按时间清理")
                        .font(.system(size: 12, weight: .semibold))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(ClipboardCacheCleanupPeriod.allCases) { period in
                            cleanupButton(period.title) {
                                app.clearClipboardCache(olderThan: period.cutoffDate)
                            }
                        }
                        cleanupButton("清理全部") {
                            app.clearClipboardCache()
                        }
                    }

                    Divider().overlay(Color.primary.opacity(0.12))

                    Toggle(
                        "按时间自动清理",
                        isOn: Binding(
                            get: { app.clipboardCacheAutoCleanupEnabled },
                            set: { app.updateClipboardCacheAutoCleanupEnabled($0) }
                        )
                    )
                    if app.clipboardCacheAutoCleanupEnabled {
                        HStack {
                            Text("自动清理周期")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Picker(
                                "自动清理周期",
                                selection: Binding(
                                    get: { app.clipboardCacheAutoCleanupPeriod },
                                    set: { app.updateClipboardCacheAutoCleanupPeriod($0) }
                                )
                            ) {
                                ForEach(ClipboardCacheCleanupPeriod.allCases) { period in
                                    Text(period.title).tag(period)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
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

    private func capacityDescription(_ bytes: Int64) -> String {
        if bytes == ClipboardCacheStore.minimumMaximumBytes {
            return "256 MB"
        }
        let gigabyte: Int64 = 1024 * 1024 * 1024
        if bytes % gigabyte == 0 {
            return "\(bytes / gigabyte) GB"
        }
        return byteDescription(bytes)
    }

    private func usageColor(for usage: ClipboardCacheUsage) -> Color {
        let fraction = min(max(Double(usage.usedBytes) / Double(max(usage.capacityBytes, 1)), 0), 1)
        let hue: Double = if fraction < 0.5 {
            0.33 - (fraction / 0.5) * 0.17
        } else if fraction < 0.8 {
            0.16 - ((fraction - 0.5) / 0.3) * 0.08
        } else {
            max(0, 0.08 - ((fraction - 0.8) / 0.2) * 0.08)
        }
        return Color(hue: hue, saturation: 0.82, brightness: 0.86)
    }

    private func cleanupButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(JarvisSecondaryButtonStyle())
    }
}
