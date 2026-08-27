import SwiftUI

private enum ClipboardCacheCleanupTimeOption: String, CaseIterable, Identifiable {
    case all
    case threeDays
    case sevenDays
    case oneMonth
    case halfYear

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .all: "全部"
        case .threeDays: ClipboardCacheCleanupPeriod.threeDays.title
        case .sevenDays: ClipboardCacheCleanupPeriod.sevenDays.title
        case .oneMonth: ClipboardCacheCleanupPeriod.oneMonth.title
        case .halfYear: ClipboardCacheCleanupPeriod.halfYear.title
        }
    }

    var period: ClipboardCacheCleanupPeriod? {
        switch self {
        case .all: nil
        case .threeDays: .threeDays
        case .sevenDays: .sevenDays
        case .oneMonth: .oneMonth
        case .halfYear: .halfYear
        }
    }
}

private enum ClipboardCacheCleanupMode: String, CaseIterable, Identifiable {
    case time
    case category

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .time: "时间"
        case .category: "分类"
        }
    }
}

private enum ClipboardCacheCleanupRequest: Identifiable {
    case category(ClipboardCacheCategory)
    case time(ClipboardCacheCleanupTimeOption)

    var id: String {
        switch self {
        case let .category(category): "category-\(category.rawValue)"
        case let .time(option): "time-\(option.rawValue)"
        }
    }

    var message: String {
        switch self {
        case let .category(category): "将清理所有未收藏的\(category.title)缓存，是否继续？"
        case let .time(option): "将清理所有未收藏且\(option.title == "全部" ? "符合条件的" : option.title)缓存，是否继续？"
        }
    }
}

struct ClipboardCacheSettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var selectedCleanupMode: ClipboardCacheCleanupMode = .time
    @State private var pendingCleanup: ClipboardCacheCleanupRequest?

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

                    HStack {
                        Picker("清理类型", selection: $selectedCleanupMode) {
                            ForEach(ClipboardCacheCleanupMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        cleanupOptions
                    }

                    Divider().overlay(Color.primary.opacity(0.12))

                    HStack(spacing: 14) {
                        Text("开启自动清理")
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
        .alert(item: $pendingCleanup) { request in
            Alert(
                title: Text("确认清理缓存"),
                message: Text(request.message),
                primaryButton: .destructive(Text("清理")) {
                    performCleanup(request)
                },
                secondaryButton: .cancel(Text("取消"))
            )
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

    private func performCleanup(_ request: ClipboardCacheCleanupRequest) {
        switch request {
        case let .category(category):
            app.clearClipboardCache(category: category)
        case let .time(option):
            app.clearClipboardCache(olderThan: option.period?.cutoffDate)
        }
    }

    private var cleanupOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                switch selectedCleanupMode {
                case .time:
                    ForEach(ClipboardCacheCleanupTimeOption.allCases) { option in
                        Button(option.title) {
                            pendingCleanup = .time(option)
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                    }
                case .category:
                    ForEach(ClipboardCacheCategory.allCases) { category in
                        Button(category.title) {
                            guard category != .favorites else { return }
                            pendingCleanup = .category(category)
                        }
                        .buttonStyle(JarvisSecondaryButtonStyle())
                        .disabled(category == .favorites)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
