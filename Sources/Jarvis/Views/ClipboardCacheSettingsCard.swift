import SwiftUI

struct ClipboardPrivacySettingsCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                preferenceRow(
                    title: "自动记录剪贴板",
                    isOn: Binding(
                        get: { app.automaticClipboardRecordingEnabled },
                        set: { app.updateAutomaticClipboardRecordingEnabled($0) }
                    )
                )
                preferenceRow(
                    title: "敏感内容默认隐藏",
                    isOn: Binding(
                        get: { app.hideSensitiveClipboardContent },
                        set: { app.updateHideSensitiveClipboardContent($0) }
                    )
                )
            }
        }
    }

    private func preferenceRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Text(title).font(SettingsTypography.itemTitle)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct ClipboardCacheSettingsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let capacityOptions = ClipboardCacheStore.supportedMaximumBytes

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                folderRow
                VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                    capacitySection
                    usageSection
                }
                cleanupSection
            }
        }
        .onAppear {
            app.refreshClipboardCacheUsage()
        }
        .animation(
            JarvisMotion.animation(JarvisMotion.content, reduceMotion: reduceMotion),
            value: app.clipboardCacheAutoCleanupPeriod
        )
    }

    private var folderRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("缓存文件夹")
                    .font(SettingsTypography.itemTitle)
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
                    .font(SettingsTypography.itemTitle)
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
                    .font(SettingsTypography.itemTitle)
                Spacer()
                Text("\(usageSummary) · \(app.clipboardCacheUsage.fileCount) 个文件")
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
        }
    }

    private var usageSummary: String {
        let usage = app.clipboardCacheUsage
        return "\(ClipboardCacheFormatting.byteDescription(usage.usedBytes)) / \(ClipboardCacheFormatting.capacityDescription(usage.capacityBytes))"
    }

    private var cleanupSection: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自动清理")
                    .font(SettingsTypography.itemTitle)
            }
            Spacer(minLength: 8)
            JarvisDropdownMenu(
                title: app.clipboardCacheAutoCleanupPeriod.title,
                options: ClipboardCacheCleanupPeriod.allCases.map {
                    JarvisDropdownOption(id: $0.id, title: $0.title)
                },
                selectionID: app.clipboardCacheAutoCleanupPeriod.id,
                accessibilityLabel: "自动清理",
                help: "选择自动清理周期",
                onSelect: { id in
                    guard let period = ClipboardCacheCleanupPeriod(rawValue: id) else { return }
                    app.updateClipboardCacheAutoCleanupPeriod(period)
                }
            )
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
