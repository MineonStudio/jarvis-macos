import AppKit
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
            VStack(alignment: .leading, spacing: 8) {
                Text("提供商")
                    .font(JarvisTypography.control)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    ForEach(AIAPIProvider.allCases) { option in
                        AIAPIProviderCapsule(
                            provider: option,
                            isSelected: provider == option,
                            isEnabled: !isLocked
                        ) {
                            provider = option
                        }
                    }
                }
            }

            apiField(title: "接口地址") {
                apiControl {
                    if isLocked {
                        apiReadOnlyValue(baseURL, placeholder: "输入 OpenAI 兼容接口地址")
                    } else {
                        TextField("输入 OpenAI 兼容接口地址", text: $baseURL)
                            .textFieldStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text("模型")
                        .font(JarvisTypography.control)
                    Spacer(minLength: 8)
                    refreshModelsButton
                }

                apiControl {
                    apiMenu(
                        title: "模型",
                        selection: $model,
                        options: modelOptions,
                        emptyTitle: "未选择模型",
                        isDisabled: isLocked || app.aiModelsLoading
                    )
                }
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
        Button("获取模型", action: refreshModels)
            .buttonStyle(JarvisSecondaryButtonStyle())
            .disabled(app.aiModelsLoading)
            .help("从当前接口地址获取可用模型列表")
    }

    private func errorRow(_ error: String) -> some View {
        Text(error)
            .font(JarvisTypography.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Spacer()

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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(JarvisTypography.control)
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

private struct AIAPIProviderCapsule: View {
    let provider: AIAPIProvider
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                providerIcon

                Text(provider.title)
                    .font(JarvisTypography.control)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.jarvisAccent)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
                isSelected ? Color.jarvisAccent.opacity(0.12) : Color.jarvisPanel.opacity(0.55),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? Color.jarvisAccent.opacity(0.55) : Color.primary.opacity(0.09),
                        lineWidth: 1
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
        .accessibilityLabel("\(provider.title)，\(isSelected ? "已选择" : "选择提供商")")
        .help(provider.title)
    }

    @ViewBuilder
    private var providerIcon: some View {
        if provider == .custom {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.jarvisAccent : Color.jarvisTextSecondary)
                .frame(width: 16, height: 16)
        } else if let image = Self.brandImage(for: provider) {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }

    private static func brandImage(for provider: AIAPIProvider) -> NSImage? {
        guard let resource = provider.brandIconResource,
              let url = Bundle.main.url(
                  forResource: resource.name,
                  withExtension: resource.fileExtension,
                  subdirectory: "AIProviderIcons"
              ),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        image.isTemplate = false
        return JarvisBrandIconMetrics.trimmed(image, cacheKey: "api.\(resource.name)")
    }
}
