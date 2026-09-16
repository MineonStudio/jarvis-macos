import SwiftUI

struct ClipboardCacheSettingsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let capacityOptions = ClipboardCacheStore.supportedMaximumBytes

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                header
                folderRow
                divider
                capacitySection
                usageSection
                divider
                cleanupSection
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

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 24, height: 24)
            Text("剪贴板缓存")
                .font(JarvisTypography.bodyEmphasis)
        }
    }

    private var divider: some View {
        Divider().overlay(Color.primary.opacity(0.12))
    }

    private var folderRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("缓存文件夹")
                    .font(JarvisTypography.sectionLabel)
                Text(app.clipboardCacheDirectoryURL.path)
                    .font(JarvisTypography.microMonospaced)
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
    }

    private var capacitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("缓存空间上限")
                    .font(JarvisTypography.sectionLabel)
                Spacer()
                Text(ClipboardCacheFormatting.capacityDescription(app.clipboardCacheMaximumBytes))
                    .font(JarvisTypography.monospacedSmall)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .contentTransition(.numericText())
                    .animation(
                        JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
                        value: app.clipboardCacheMaximumBytes
                    )
            }
            Slider(value: capacityBinding, in: 0 ... Double(capacityOptions.count - 1), step: 1)
        }
    }

    private var capacityBinding: Binding<Double> {
        Binding(
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
        )
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("当前占用")
                    .font(JarvisTypography.sectionLabel)
                Spacer()
                Text(usageSummary)
                    .font(JarvisTypography.monospacedSmall)
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
                .font(JarvisTypography.micro)
                .foregroundStyle(Color.jarvisTextSecondary)
                .contentTransition(.numericText())
                .animation(
                    JarvisMotion.animation(JarvisMotion.feedback, reduceMotion: reduceMotion),
                    value: app.clipboardCacheUsage.fileCount
                )
        }
    }

    private var usageSummary: String {
        let usage = app.clipboardCacheUsage
        return "\(ClipboardCacheFormatting.byteDescription(usage.usedBytes)) / \(ClipboardCacheFormatting.capacityDescription(usage.capacityBytes))"
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("开启自动清理")
                    .font(JarvisTypography.sectionLabel)
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

    private func usageColor(for usage: ClipboardCacheUsage) -> Color {
        let fraction = usage.fraction
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
