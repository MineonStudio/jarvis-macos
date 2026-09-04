import Foundation

struct HermesCurrentModel: Equatable, Sendable {
    var provider: String
    var model: String
    var baseURL: String

    var isPlaceholder: Bool {
        let provider = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isEmpty, model.isEmpty {
            return true
        }
        return provider == "openai" && (model.isEmpty || model == AIAPIConfiguration.defaultModel)
    }
}

struct HermesInferenceBinding: Equatable, Sendable {
    var provider: String
    var apiKeyEnv: String
    var baseURLEnv: String
    var baseURL: String
    var model: String
}

enum HermesInferenceProvider {
    static let apiKeyEnvNames = [
        "OPENAI_API_KEY",
        "DEEPSEEK_API_KEY",
        "OPENROUTER_API_KEY",
        "ANTHROPIC_API_KEY",
        "GROQ_API_KEY"
    ]

    static func binding(for configuration: AIAPIConfiguration) -> HermesInferenceBinding {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredSlug = HermesProviderCatalog.slug(forEndpoint: configuration.endpoint)
        if let descriptor = HermesProviderCatalog.descriptor(for: inferredSlug) {
            return HermesInferenceBinding(
                provider: descriptor.slug,
                apiKeyEnv: descriptor.apiKeyEnv,
                baseURLEnv: descriptor.baseURLEnv,
                baseURL: descriptor.baseURL.isEmpty ? configuration.openAIBaseURL : descriptor.baseURL,
                model: model
            )
        }

        let host = host(from: configuration.endpoint) ?? host(from: configuration.openAIBaseURL) ?? ""
        let baseURL = configuration.openAIBaseURL

        if host.contains("deepseek") {
            return HermesInferenceBinding(
                provider: "deepseek",
                apiKeyEnv: "DEEPSEEK_API_KEY",
                baseURLEnv: "OPENAI_BASE_URL",
                baseURL: baseURL,
                model: model
            )
        }
        if host.contains("openrouter") {
            return HermesInferenceBinding(
                provider: "openrouter",
                apiKeyEnv: "OPENROUTER_API_KEY",
                baseURLEnv: "OPENAI_BASE_URL",
                baseURL: baseURL,
                model: model
            )
        }
        if host.contains("opencode.ai") {
            return HermesInferenceBinding(
                provider: "opencode-free",
                apiKeyEnv: "",
                baseURLEnv: "OPENAI_BASE_URL",
                baseURL: "https://opencode.ai/zen/v1",
                model: model
            )
        }
        return HermesInferenceBinding(
            provider: "openai",
            apiKeyEnv: "OPENAI_API_KEY",
            baseURLEnv: "OPENAI_BASE_URL",
            baseURL: baseURL,
            model: model
        )
    }

    static func configuration(
        env: [String: String],
        yaml: [String: String]
    ) -> AIAPIConfiguration? {
        let provider = (yaml["provider"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredKeyEnv = switch provider {
        case "deepseek": "DEEPSEEK_API_KEY"
        case "openrouter": "OPENROUTER_API_KEY"
        case "anthropic": "ANTHROPIC_API_KEY"
        default: "OPENAI_API_KEY"
        }

        let apiKey = firstNonEmpty(env, keys: [preferredKeyEnv] + apiKeyEnvNames)
        guard !apiKey.isEmpty else { return nil }

        var baseURL = firstNonEmpty(env, keys: ["OPENAI_BASE_URL", "DEEPSEEK_BASE_URL"])
        if baseURL.isEmpty {
            baseURL = yaml["base_url"] ?? ""
        }
        let endpoint: String = if baseURL.isEmpty {
            defaultEndpoint(for: provider)
        } else if let normalized = OpenAICompatibleAPIClient.normalizedEndpointURL(from: baseURL) {
            normalized.absoluteString
        } else {
            AIAPIConfiguration(
                endpoint: baseURL,
                model: "",
                apiKey: ""
            ).openAIBaseURL + "/chat/completions"
        }
        let model = yaml["default"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIAPIConfiguration(
            endpoint: endpoint,
            model: (model?.isEmpty == false ? model : nil) ?? defaultModel(for: provider),
            apiKey: apiKey
        )
    }

    /// Recovers the configured (paid) provider from Hermes even if yaml currently
    /// points at OpenCode free models. Env keys are not overwritten on free switch.
    static func paidConfiguration(
        env: [String: String],
        yaml: [String: String]
    ) -> AIAPIConfiguration? {
        let apiKey = firstNonEmpty(env, keys: apiKeyEnvNames)
        guard !apiKey.isEmpty else { return nil }

        let yamlProvider = (yaml["provider"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let yamlBase = (yaml["base_url"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var baseURL = firstNonEmpty(env, keys: ["OPENAI_BASE_URL", "DEEPSEEK_BASE_URL"])
        if baseURL.isEmpty || AIAPIConfiguration.isKeylessEndpoint(baseURL) {
            if !yamlBase.isEmpty,
               !AIAPIConfiguration.isKeylessEndpoint(yamlBase),
               yamlProvider != "opencode-free"
            {
                baseURL = yamlBase
            } else if !firstNonEmpty(env, keys: ["DEEPSEEK_API_KEY"]).isEmpty {
                baseURL = "https://api.deepseek.com/v1"
            } else if !firstNonEmpty(env, keys: ["OPENROUTER_API_KEY"]).isEmpty {
                baseURL = "https://openrouter.ai/api/v1"
            } else {
                return nil
            }
        }
        guard !AIAPIConfiguration.isKeylessEndpoint(baseURL) else { return nil }

        let endpoint: String = if let normalized = OpenAICompatibleAPIClient.normalizedEndpointURL(from: baseURL) {
            normalized.absoluteString
        } else {
            AIAPIConfiguration(
                endpoint: baseURL,
                model: "",
                apiKey: ""
            ).openAIBaseURL + "/chat/completions"
        }

        let yamlModel = yaml["default"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model: String = if !yamlModel.isEmpty,
                               !HermesFreeModelCatalog.isAnonymousFreeModel(yamlModel),
                               yamlProvider != "opencode-free"
        {
            yamlModel
        } else {
            defaultModel(for: host(from: endpoint)?.contains("deepseek") == true ? "deepseek" : "openai")
        }

        return AIAPIConfiguration(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey
        )
    }

    static func hasAPIKey(in env: [String: String]) -> Bool {
        apiKeyEnvNames.contains { key in
            !(env[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func upsertUserName(_ name: String, into markdown: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var replaced = false
        let lines = markdown.components(separatedBy: .newlines).map { line -> String in
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard stripped.lowercased().hasPrefix("- name:") else { return line }
            replaced = true
            return "- Name: \(trimmedName)"
        }
        if replaced {
            return lines.joined(separator: "\n")
        }
        let body = markdown.trimmingCharacters(in: CharacterSet.newlines)
        if body.isEmpty {
            return "# USER.md\n\n- Name: \(trimmedName)\n"
        }
        return body + "\n- Name: \(trimmedName)\n"
    }

    static func parseUserName(from markdown: String) -> String? {
        for line in markdown.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard stripped.lowercased().hasPrefix("- name:") else { continue }
            let value = String(stripped.dropFirst("- name:".count)).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func host(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmed)?.host {
            return host.lowercased()
        }
        return nil
    }

    private static func firstNonEmpty(_ env: [String: String], keys: [String]) -> String {
        for key in keys {
            let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func defaultEndpoint(for provider: String) -> String {
        switch provider {
        case "deepseek": "https://api.deepseek.com/v1/chat/completions"
        case "openrouter": "https://openrouter.ai/api/v1/chat/completions"
        default: AIAPIConfiguration.defaultEndpoint
        }
    }

    private static func defaultModel(for provider: String) -> String {
        switch provider {
        case "deepseek": "deepseek-chat"
        default: AIAPIConfiguration.defaultModel
        }
    }
}

struct HermesBot: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let avatarPath: String?

    var isJarvisProfile: Bool {
        id == HermesAdapter.profileName
    }
}

struct HermesChatAttachment: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case file
        case folder
        case image
        case url
    }

    let id: UUID
    var kind: Kind
    var fileURL: URL?
    var remoteURL: String?
    var displayName: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        fileURL: URL? = nil,
        remoteURL: String? = nil,
        displayName: String
    ) {
        self.id = id
        self.kind = kind
        self.fileURL = fileURL
        self.remoteURL = remoteURL
        self.displayName = displayName
    }

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp"
    ]

    static func kind(forFileURL url: URL) -> Kind {
        if url.hasDirectoryPath {
            return .folder
        }
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            return .image
        }
        return .file
    }

    var systemImage: String {
        switch kind {
        case .file: "doc"
        case .folder: "folder"
        case .image: "photo"
        case .url: "link"
        }
    }
}

enum HermesChatPayload {
    struct Result: Equatable, Sendable {
        var query: String
        var imagePaths: [String]
        var displayText: String
        var attachmentNames: [String]
    }

    static func compose(draft: String, attachments: [HermesChatAttachment]) -> Result {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }
        var imagePaths: [String] = []
        var names: [String] = []
        for item in attachments {
            names.append(item.displayName)
            switch item.kind {
            case .image:
                if let path = item.fileURL?.path, !path.isEmpty {
                    if !imagePaths.isEmpty {
                        lines.append("用户附加了图片：\(path)")
                    }
                    imagePaths.append(path)
                }
            case .file:
                if let path = item.fileURL?.path, !path.isEmpty {
                    lines.append("用户附加了文件：\(path)")
                }
            case .folder:
                if let path = item.fileURL?.path, !path.isEmpty {
                    lines.append("用户附加了文件夹：\(path)")
                }
            case .url:
                if let url = item.remoteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !url.isEmpty
                {
                    lines.append("用户附加了链接：\(url)")
                }
            }
        }
        var query = lines.joined(separator: "\n")
        if query.isEmpty, !imagePaths.isEmpty {
            let listed = imagePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            query = "[User attached image: \(listed)]"
        }
        let display = trimmed.isEmpty ? names.joined(separator: "、") : trimmed
        return Result(
            query: query,
            imagePaths: imagePaths,
            displayText: display,
            attachmentNames: names
        )
    }
}

struct HermesChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String
    var attachmentNames: [String]

    init(id: UUID = UUID(), role: Role, text: String, attachmentNames: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.attachmentNames = attachmentNames
    }
}
