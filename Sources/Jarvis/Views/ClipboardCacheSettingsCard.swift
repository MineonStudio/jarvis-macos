import SwiftUI

struct ClipboardCacheSettingsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let capacityOptions = ClipboardCacheStore.supportedMaximumBytes

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 24, height: 24)
                    Text("剪贴板缓存")
                        .font(JarvisTypography.bodyEmphasis)
                }

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
                            .contentTransition(.numericText())
                            .animation(
                                JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
                                value: app.clipboardCacheMaximumBytes
                            )
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
                                .animation(
                                    JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
                                    value: usage.fraction
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .frame(height: 8)
                    Text("已保存 \(app.clipboardCacheUsage.fileCount) 个缓存文件")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .contentTransition(.numericText())
                        .animation(
                            JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
                            value: app.clipboardCacheUsage.fileCount
                        )
                }

                Divider().overlay(Color.primary.opacity(0.12))

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Text("开启自动清理")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        JarvisDropdownMenu(
                            title: app.clipboardCacheAutoCleanupPeriod.title,
                            options: ClipboardCacheCleanupPeriod.allCases.map {
                                JarvisDropdownOption(id: $0.id, title: $0.title)
                            },
                            selectionID: app.clipboardCacheAutoCleanupPeriod.id,
                            accessibilityLabel: "自动清理周期",
                            help: "选择自动清理周期",
                            onSelect: { id in
                                guard let period = ClipboardCacheCleanupPeriod(rawValue: id) else { return }
                                app.updateClipboardCacheAutoCleanupPeriod(period)
                            }
                        )
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { app.clipboardCacheAutoCleanupEnabled },
                                set: { app.updateClipboardCacheAutoCleanupEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
            }
        }
        .onAppear {
            app.refreshClipboardCacheUsage()
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: app.clipboardCacheAutoCleanupEnabled
        )
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
}
