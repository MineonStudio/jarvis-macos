import AppKit
import Combine
import SwiftUI
import Translation

/// Forwards row `objectWillChange` so `busyCount` updates the parent card.
@MainActor
final class LanguagePackSettingsStore: ObservableObject {
    private let models: [ScreenshotTranslationLanguage: LanguagePackRowModel]
    private var cancellables: Set<AnyCancellable> = []

    init(service: any LanguagePackService = SystemLanguagePackService()) {
        var models: [ScreenshotTranslationLanguage: LanguagePackRowModel] = [:]
        for target in ScreenshotTranslationLanguage.packTargets {
            models[target] = LanguagePackRowModel(target: target, service: service)
        }
        self.models = models
        for model in models.values {
            model.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    var busyCount: Int {
        models.values.filter(\.isBusy).count
    }

    func model(for target: ScreenshotTranslationLanguage) -> LanguagePackRowModel {
        models[target]!
    }

    func refreshAll() async {
        for model in models.values {
            await model.refresh()
        }
    }

    func tearDownAll() {
        for model in models.values {
            model.tearDown()
        }
    }
}

struct ScreenshotLanguagePackSettingsCard: View {
    @StateObject private var store = LanguagePackSettingsStore()
    @AppStorage(ScreenshotTranslationConfiguration.targetLanguageKey)
    private var defaultTargetRaw = ScreenshotTranslationLanguage.simplifiedChinese.rawValue

    private var defaultTarget: ScreenshotTranslationLanguage {
        ScreenshotTranslationLanguage(rawValue: defaultTargetRaw) ?? .simplifiedChinese
    }

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 24, height: 24)
                    Text("截图翻译语言包")
                        .font(JarvisTypography.bodyEmphasis)
                    Spacer()
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(store.busyCount > 0)
                    .help("重新检测")
                }

                VStack(spacing: 8) {
                    ForEach(ScreenshotTranslationLanguage.packTargets) { target in
                        LanguagePackRowView(
                            model: store.model(for: target),
                            isDefaultTarget: defaultTarget == target
                        )
                    }
                }
            }
        }
        .task { await store.refreshAll() }
        .onDisappear { store.tearDownAll() }
    }
}

private struct LanguagePackRowView: View {
    @ObservedObject var model: LanguagePackRowModel
    let isDefaultTarget: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(model.target.title)
                .font(JarvisTypography.body)
                .foregroundStyle(isDefaultTarget ? Color.primary : Color.secondary)
            if isDefaultTarget {
                Text("当前默认")
                    .font(JarvisTypography.caption)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            statusView
            if model.phase == .installed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Uninstalled pairs can only be prepared via `.translationTask`.
        .translationTask(model.sessionConfiguration) { session in
            await model.consumeSession(
                SystemLanguagePackSessionHandler(target: model.target, session: session)
            )
        }
        .id("language-pack-\(model.target.rawValue)-\(model.channelGeneration)")
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.phase {
        case .checking:
            ProgressView().controlSize(.small)
            Text("检测中").font(JarvisTypography.control).foregroundStyle(Color.secondary)
        case .installed:
            EmptyView()
        case .supported:
            Button("下载") { model.startDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        case .unsupported:
            Text("系统不支持")
                .font(JarvisTypography.control)
                .foregroundStyle(Color.secondary)
                .fixedSize()
        case .downloading:
            ProgressView().controlSize(.small)
            Text("下载中…").font(JarvisTypography.control).foregroundStyle(Color.secondary)
            Button("取消") { model.cancelDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        case let .failed(message):
            Text(message)
                .font(JarvisTypography.control)
                .foregroundStyle(Color.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)
            Button("重试") { model.startDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }
}
