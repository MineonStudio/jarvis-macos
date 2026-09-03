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

                Text("默认使用系统本地翻译，首次可能需要下载语言包。下面的备选 API 仅在系统不支持该语言时使用。")
                    .font(JarvisTypography.control)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
            Text("系统不支持，走 AI 备选")
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

struct ScreenshotAITranslationAPISettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var endpoint = ScreenshotTranslationConfiguration.defaultEndpoint
    @State private var model = ScreenshotTranslationConfiguration.defaultModel
    @State private var apiKey = ""

    private var canUseConfiguration: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (app.screenshotTranslationAPIKeyConfigured
                || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 24, height: 24)
                    Text("备选 API")
                        .font(JarvisTypography.bodyEmphasis)
                }

                HStack(spacing: 10) {
                    Text("接口地址")
                        .font(JarvisTypography.control)
                        .frame(width: 70, alignment: .leading)
                    TextField(
                        ScreenshotTranslationConfiguration.defaultEndpoint,
                        text: $endpoint
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLocked)
                }

                HStack(spacing: 10) {
                    Text("模型")
                        .font(JarvisTypography.control)
                        .frame(width: 70, alignment: .leading)
                    TextField(
                        ScreenshotTranslationConfiguration.defaultModel,
                        text: $model
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLocked)
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    Text("API Key")
                        .font(JarvisTypography.control)
                        .frame(width: 70, alignment: .leading)
                    SecureField(
                        app.screenshotTranslationAPIKeyMask.isEmpty
                            ? "输入 API Key"
                            : app.screenshotTranslationAPIKeyMask,
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLocked)

                    if isLocked {
                        Button("编辑", action: beginEditing)
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    } else {
                        Button("保存", action: saveSettings)
                            .buttonStyle(JarvisSecondaryButtonStyle())
                            .disabled(!canUseConfiguration)
                    }

                    Button {
                        Task {
                            await app.testScreenshotTranslationConnection(
                                endpoint: endpoint,
                                model: model,
                                apiKey: apiKey
                            )
                        }
                    } label: {
                        if app.screenshotTranslationConnectionTesting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 56)
                        } else {
                            Text("测试连接")
                        }
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(!canUseConfiguration || app.screenshotTranslationConnectionTesting)
                }
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: app.screenshotTranslationSettingsLocked) { _, isLocked in
            if isLocked {
                loadDraft()
            }
        }
    }

    private var isLocked: Bool {
        app.screenshotTranslationSettingsLocked
    }

    private func loadDraft() {
        endpoint = app.screenshotTranslationEndpoint
        model = app.screenshotTranslationModel
        apiKey = ""
    }

    private func beginEditing() {
        loadDraft()
        app.editScreenshotTranslationSettings()
    }

    private func saveSettings() {
        guard app.saveScreenshotTranslationSettings(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey
        ) else {
            return
        }
        apiKey = ""
    }
}
