import Combine
import SwiftUI
import Translation

/// Forwards row `objectWillChange` so each row updates while its system status changes.
@MainActor
final class LanguagePackSettingsStore: ObservableObject {
    private let models: [ScreenshotTranslationLanguage: LanguagePackRowModel]
    private var cancellables: Set<AnyCancellable> = []
    private var isWaitingForSystemSettingsReturn = false

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

    func model(for target: ScreenshotTranslationLanguage) -> LanguagePackRowModel {
        models[target]!
    }

    func checkAll() async {
        for model in models.values {
            await model.refresh()
        }
    }

    func openLanguageSettings() -> Bool {
        isWaitingForSystemSettingsReturn = true
        let didOpen = SystemLanguagePackService.openLanguageSettings()
        if !didOpen {
            isWaitingForSystemSettingsReturn = false
        }
        return didOpen
    }

    func refreshAfterSystemSettingsReturn() {
        guard isWaitingForSystemSettingsReturn else {
            return
        }
        isWaitingForSystemSettingsReturn = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            await self?.checkAll()
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

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: SettingsFormMetrics.cardContentSpacing) {
                SettingsCardHeader(title: "截图翻译语言包", systemImage: "character.bubble")

                VStack(spacing: 8) {
                    ForEach(ScreenshotTranslationLanguage.packTargets) { target in
                        LanguagePackRowView(
                            model: store.model(for: target),
                            openLanguageSettings: store.openLanguageSettings
                        )
                    }
                }
            }
        }
        .task { await store.checkAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshAfterSystemSettingsReturn()
        }
        .onDisappear { store.tearDownAll() }
    }
}

private struct LanguagePackRowView: View {
    @ObservedObject var model: LanguagePackRowModel
    let openLanguageSettings: () -> Bool
    @State private var showingSettingsOpenFailure = false

    var body: some View {
        HStack(spacing: 10) {
            Text(model.target.title)
                .font(SettingsTypography.itemTitle)
                .foregroundStyle(Color.primary)
            Spacer()
            statusView
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
        .alert("无法打开系统设置", isPresented: $showingSettingsOpenFailure) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("无法打开“系统设置”的“语言与地区”页面，请稍后重试。")
        }
        .id("language-pack-\(model.target.rawValue)-\(model.channelGeneration)")
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.phase {
        case .checking:
            Text("检测中").font(JarvisTypography.control).foregroundStyle(Color.secondary)
        case .installed:
            Button("移除") {
                showingSettingsOpenFailure = !openLanguageSettings()
            }
            .buttonStyle(JarvisSecondaryButtonStyle())
            .accessibilityLabel("在系统设置中移除\(model.target.title)语言包")
            .help("打开系统设置的语言与地区页面管理翻译语言包")
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
            Button("重试") { model.startDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }
}
