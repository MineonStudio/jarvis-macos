import SwiftUI

struct AIAPISettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var name = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var showingDeleteConfirmation = false

    private var hasStoredConfiguration: Bool {
        app.aiAPIKeyConfigured || AIAPIConfiguration.hasStoredAPIEndpoint()
    }

    private var effectiveBaseURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AIAPIConfiguration.defaultBaseURL : trimmed
    }

    private var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AIAPIConfiguration.defaultModel : trimmed
    }

    private var canUseConfiguration: Bool {
        (app.aiAPIKeyConfigured
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && OpenAICompatibleAPIClient.normalizedEndpointURL(from: effectiveBaseURL) != nil
            && !effectiveModel.isEmpty
    }

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardHeader(title: "API 配置", systemImage: "key")

                fieldRow(title: "名称") {
                    TextField("例如：DeepSeek", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLocked)
                }

                fieldRow(title: "base_url") {
                    TextField(AIAPIConfiguration.defaultBaseURL, text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLocked)
                }

                fieldRow(title: "模型") {
                    TextField(AIAPIConfiguration.defaultModel, text: $model)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isLocked)
                }

                fieldRow(title: "Key") {
                    SecureField(
                        app.aiAPIKeyMask.isEmpty ? "输入 API Key" : app.aiAPIKeyMask,
                        text: $apiKey
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLocked)
                }

                HStack(spacing: 8) {
                    Spacer(minLength: 82)

                    if isLocked {
                        Button("编辑配置", action: beginEditing)
                            .buttonStyle(JarvisSecondaryButtonStyle())
                    } else {
                        Button("保存配置", action: saveSettings)
                            .buttonStyle(JarvisSecondaryButtonStyle())
                            .disabled(!canUseConfiguration)
                    }

                    Button {
                        Task {
                            await app.testAIAPIConnection(
                                endpoint: effectiveBaseURL,
                                model: effectiveModel,
                                apiKey: apiKey
                            )
                        }
                    } label: {
                        if app.aiConnectionTesting {
                            ProgressView()
                                .controlSize(.small)
                                .frame(minWidth: 56)
                        } else {
                            Text("测试连接")
                        }
                    }
                    .buttonStyle(JarvisSecondaryButtonStyle())
                    .disabled(!canUseConfiguration || app.aiConnectionTesting)

                    if hasStoredConfiguration {
                        Button("删除配置", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .buttonStyle(JarvisToolbarButtonStyle(tint: .red))
                    }
                }
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: app.aiSettingsLocked) { _, isLocked in
            if isLocked {
                loadDraft()
            }
        }
        .confirmationDialog(
            "删除 API 配置？",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除配置", role: .destructive) {
                if app.deleteAIAPIConfiguration() {
                    loadDraft()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 API Key、接口地址、模型和本地模型缓存，并清除 Hermes 中由 JARVIS 同步的配置。")
        }
    }

    private var isLocked: Bool {
        app.aiSettingsLocked
    }

    private func fieldRow(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(JarvisTypography.control)
                .frame(width: 72, alignment: .leading)
            content()
        }
    }

    private func loadDraft() {
        if hasStoredConfiguration {
            name = app.providerName
            let configuration = AIAPIConfiguration(
                endpoint: app.providerEndpoint,
                model: app.providerModel,
                apiKey: ""
            )
            baseURL = configuration.openAIBaseURL
            model = app.providerModel
        } else {
            name = ""
            baseURL = ""
            model = ""
        }
        apiKey = ""
    }

    private func beginEditing() {
        loadDraft()
        app.editAIAPISettings()
    }

    private func saveSettings() {
        guard app.saveProviderSettings(
            name: name,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey
        ) else {
            return
        }
        apiKey = ""
    }
}
