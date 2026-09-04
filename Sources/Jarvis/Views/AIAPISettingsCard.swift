import SwiftUI

struct AIAPISettingsCard: View {
    @EnvironmentObject private var app: AppModel
    @State private var name = ""
    @State private var baseURL = AIAPIConfiguration.defaultBaseURL
    @State private var model = AIAPIConfiguration.defaultModel
    @State private var apiKey = ""

    private var canUseConfiguration: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (app.aiAPIKeyConfigured
                || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardHeader(title: "API 配置", systemImage: "key")

                fieldRow(title: "名称") {
                    TextField("DeepSeek", text: $name)
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
                    HStack(spacing: 8) {
                        SecureField(
                            app.aiAPIKeyMask.isEmpty ? "输入 API Key" : app.aiAPIKeyMask,
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

                        if app.aiAPIKeyConfigured, !isLocked {
                            Button("清除") {
                                guard app.clearAIAPIKey() else { return }
                                apiKey = ""
                                loadDraft()
                            }
                            .buttonStyle(JarvisSecondaryButtonStyle())
                        }

                        Button {
                            Task {
                                await app.testAIAPIConnection(
                                    endpoint: baseURL,
                                    model: model,
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
        name = app.providerName
        let configuration = AIAPIConfiguration(
            endpoint: app.providerEndpoint,
            model: app.providerModel,
            apiKey: ""
        )
        baseURL = configuration.openAIBaseURL
        model = app.providerModel
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
