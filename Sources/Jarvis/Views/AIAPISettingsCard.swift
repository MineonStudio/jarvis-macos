import SwiftUI

struct AIAPISettingsCard: View {
    @Environment(AppModel.self) private var app
    @State private var provider: AIAPIProvider = .openAI
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var showingDeleteConfirmation = false

    private var hasStoredConfiguration: Bool {
        app.aiAPIKeyConfigured || AIAPIConfiguration.hasStoredAPIEndpoint()
    }

    private var effectiveBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canUseConfiguration: Bool {
        (app.aiAPIKeyConfigured
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && OpenAICompatibleAPIClient.normalizedEndpointURL(
                from: effectiveBaseURL,
                provider: provider
            ) != nil
            && !effectiveModel.isEmpty
    }

    private var canRefreshModels: Bool {
        (app.aiAPIKeyConfigured
            || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && OpenAICompatibleAPIClient.normalizedModelsURL(
                from: effectiveBaseURL,
                provider: provider
            ) != nil
    }

    private var modelOptions: [String] {
        if model.isEmpty {
            return app.availableAIModels
        }
        return [model] + app.availableAIModels.filter { $0 != model }
    }

    var body: some View {
        JarvisCard {
            VStack(alignment: .leading, spacing: 12) {
                SettingsCardHeader(title: "API 配置", systemImage: "key")
                fieldsSection
                if let error = app.aiModelsRefreshError {
                    errorRow(error)
                }
                actionsRow
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: provider) { _, newProvider in
            guard !isLocked else { return }
            baseURL = newProvider.defaultBaseURL
            model = ""
            app.clearAIModels()
        }
        .onChange(of: app.aiSettingsLocked) { _, isLocked in
            if isLocked {
                loadDraft()
            }
        }
        .onChange(of: app.availableAIModels) { _, models in
            guard let first = models.first, !models.contains(model) else { return }
            model = first
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
            Text("将删除 API Key、提供商、接口地址和模型配置。")
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            apiField(title: "提供商") {
                apiControl {
                    apiMenu(
                        title: "提供商",
                        selection: Binding(
                            get: { provider.title },
                            set: { selectedTitle in
                                guard let selectedProvider = AIAPIProvider.allCases.first(where: {
                                    $0.title == selectedTitle
                                }) else {
                                    return
                                }
                                provider = selectedProvider
                            }
                        ),
                        options: AIAPIProvider.allCases.map(\.title),
                        isDisabled: isLocked
                    )
                }
            }

            apiField(title: "base_url") {
                apiControl {
                    if isLocked {
                        apiReadOnlyValue(baseURL, placeholder: "输入 OpenAI 兼容 base_url")
                    } else {
                        TextField("输入 OpenAI 兼容 base_url", text: $baseURL)
                            .textFieldStyle(.plain)
                    }
                }
            }

            apiField(title: "模型") {
                HStack(spacing: 8) {
                    apiControl {
                        apiMenu(
                            title: "模型",
                            selection: $model,
                            options: modelOptions,
                            emptyTitle: "未选择模型",
                            isDisabled: isLocked || app.aiModelsLoading
                        )
                    }
                    refreshModelsButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            apiField(title: "Key") {
                apiControl {
                    if isLocked {
                        apiReadOnlyValue(app.aiAPIKeyMask, placeholder: "输入 API Key")
                    } else {
                        // Show the stored key as a mask so an existing key is
                        // visible while editing; saving with an empty field
                        // keeps it.
                        SecureField(
                            app.aiAPIKeyMask.isEmpty ? "输入 API Key" : app.aiAPIKeyMask,
                            text: $apiKey
                        )
                        .textFieldStyle(.plain)
                    }
                }
            }
        }
    }

    private var refreshModelsButton: some View {
        Button(action: refreshModels) {
            HStack(spacing: 6) {
                if app.aiModelsLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("获取模型")
            }
        }
        .buttonStyle(JarvisSecondaryButtonStyle())
        .disabled(isLocked || app.aiModelsLoading || !canRefreshModels)
        .help("获取最新模型列表")
    }

    private func errorRow(_ error: String) -> some View {
        Text(error)
            .font(JarvisTypography.caption)
            .foregroundStyle(.red)
            .padding(.leading, 82)
    }

    private var actionsRow: some View {
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
                        provider: provider,
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
                .buttonStyle(JarvisSecondaryButtonStyle(tint: .red))
            }
        }
    }

    private var isLocked: Bool {
        app.aiSettingsLocked
    }

    private func apiField(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(JarvisTypography.control)
                .frame(width: 72, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func apiMenu(
        title: String,
        selection: Binding<String>,
        options: [String],
        emptyTitle: String = "",
        isDisabled: Bool
    ) -> some View {
        if isLocked {
            Text(selection.wrappedValue.isEmpty ? emptyTitle : selection.wrappedValue)
                .font(JarvisTypography.control)
                .foregroundStyle(Color.jarvisTextSecondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            JarvisDropdownMenu(
                title: selection.wrappedValue.isEmpty ? emptyTitle : selection.wrappedValue,
                options: options.map {
                    JarvisDropdownOption(id: $0, title: $0)
                },
                selectionID: options.contains(selection.wrappedValue) ? selection.wrappedValue : nil,
                accessibilityLabel: title,
                help: "选择\(title)",
                // Fetched model identifiers run long; let the control grow
                // past the toolbar cap so the selection stays readable.
                maximumControlWidth: 480,
                isEnabled: !isDisabled,
                onSelect: { selectedValue in
                    selection.wrappedValue = selectedValue
                }
            )
            // The menu sizes itself to its content, so a plain
            // `maxWidth: .infinity` frame centers it inside the control box.
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
        }
    }

    private func apiReadOnlyValue(_ value: String, placeholder: String) -> some View {
        Text(value.isEmpty ? placeholder : value)
            .font(JarvisTypography.control)
            .foregroundStyle(Color.jarvisTextSecondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func apiControl(
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(.horizontal, 8)
            .background(
                Color.jarvisPanel.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }

    private func loadDraft() {
        if hasStoredConfiguration {
            provider = app.apiProvider
            let configuration = AIAPIConfiguration(
                endpoint: app.providerEndpoint,
                model: app.providerModel,
                apiKey: "",
                providerID: app.apiProvider.rawValue
            )
            baseURL = configuration.openAIBaseURL
            model = app.providerModel
        } else {
            provider = .openAI
            baseURL = provider.defaultBaseURL
            model = ""
        }
        apiKey = ""
        app.clearAIModels()
    }

    private func beginEditing() {
        loadDraft()
        app.editAIAPISettings()
    }

    private func refreshModels() {
        guard canRefreshModels else { return }
        app.refreshAIModels(
            provider: provider,
            baseURL: effectiveBaseURL,
            selectedModel: effectiveModel,
            apiKey: apiKey
        )
    }

    private func saveSettings() {
        guard app.saveProviderSettings(
            provider: provider,
            baseURL: effectiveBaseURL,
            model: effectiveModel,
            apiKey: apiKey
        ) else {
            return
        }
        apiKey = ""
    }
}
