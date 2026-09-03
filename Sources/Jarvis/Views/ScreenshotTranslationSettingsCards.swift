import AppKit
import Combine
import SwiftUI
import Translation

// MARK: - 系统翻译语言包（下载与检测）

// 卡片级容器：创建 5 个行模型并把子模型的发布转发为自己的 objectWillChange，
// 父视图才能观察到 busyCount 等派生值（@ObservedObject 只订阅直接持有的对象）
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
    @State private var defaultTarget = ScreenshotTranslationLanguage(
        rawValue: UserDefaults.standard.string(
            forKey: ScreenshotTranslationConfiguration.targetLanguageKey
        ) ?? ""
    ) ?? .simplifiedChinese

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

// 纯渲染行：状态全在 LanguagePackRowModel，行内无任何 @State 状态
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
        .frame(height: 30)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        // 会话通道：模型发布 configuration 驱动本行 translationTask；到手的 TranslationSession
        // 包装成句柄交回模型（TranslationSession 无"未安装对"公开构造，只能经 SwiftUI 获取）
        // .id(channelGeneration)：每次发起下载重建本视图，新挂载 + 非空配置必然派发新会话，
        // 不受"配置 Equatable 相等则不重启"的限制（取消后重试的关键）
        .translationTask(model.sessionConfiguration) { session in
            await model.handOver(
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
        case .failed(let message):
            Text("下载失败")
                .font(JarvisTypography.control)
                .foregroundStyle(Color.red)
                .help(message)
            Button("重试") { model.startDownload() }
                .buttonStyle(JarvisSecondaryButtonStyle())
        }
    }
}

// MARK: - AI 备选 API

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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 24, height: 24)
                    Text("API KEY 配置")
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
        ) else { return }
        apiKey = ""
    }
}
