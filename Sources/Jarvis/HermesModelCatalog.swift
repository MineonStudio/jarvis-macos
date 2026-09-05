import Foundation

struct HermesProviderDescriptor: Equatable, Sendable {
    var slug: String
    var groupTitle: String
    var baseURL: String
    var apiKeyEnv: String
    var baseURLEnv: String
    var isKeyless: Bool
    var usesExternalAuth: Bool

    var chatCompletionsURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return "" }
        if trimmed.lowercased().hasSuffix("/chat/completions") {
            return trimmed
        }
        return trimmed + "/chat/completions"
    }
}

enum HermesProviderCatalog {
    static let descriptors: [String: HermesProviderDescriptor] = {
        let items: [HermesProviderDescriptor] = [
            .init(
                slug: "deepseek",
                groupTitle: "DeepSeek",
                baseURL: "https://api.deepseek.com/v1",
                apiKeyEnv: "DEEPSEEK_API_KEY",
                baseURLEnv: "OPENAI_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "openai-api",
                groupTitle: "OpenAI",
                baseURL: "https://api.openai.com/v1",
                apiKeyEnv: "OPENAI_API_KEY",
                baseURLEnv: "OPENAI_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "openai",
                groupTitle: "OpenAI",
                baseURL: "https://api.openai.com/v1",
                apiKeyEnv: "OPENAI_API_KEY",
                baseURLEnv: "OPENAI_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "openai-codex",
                groupTitle: "OpenAI",
                baseURL: "https://chatgpt.com/backend-api/codex",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: false,
                usesExternalAuth: true
            ),
            .init(
                slug: "openrouter",
                groupTitle: "OpenRouter",
                baseURL: "https://openrouter.ai/api/v1",
                apiKeyEnv: "OPENROUTER_API_KEY",
                baseURLEnv: "OPENAI_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "opencode-free",
                groupTitle: "OpenCode",
                baseURL: "https://opencode.ai/zen/v1",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: true,
                usesExternalAuth: false
            ),
            .init(
                slug: "opencode-zen",
                groupTitle: "OpenCode",
                baseURL: "https://opencode.ai/zen/v1",
                apiKeyEnv: "OPENCODE_ZEN_API_KEY",
                baseURLEnv: "OPENCODE_ZEN_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "opencode-go",
                groupTitle: "OpenCode",
                baseURL: "https://opencode.ai/zen/go/v1",
                apiKeyEnv: "OPENCODE_GO_API_KEY",
                baseURLEnv: "OPENCODE_GO_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "copilot",
                groupTitle: "GitHub Copilot",
                baseURL: "https://api.githubcopilot.com",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: false,
                usesExternalAuth: true
            ),
            .init(
                slug: "copilot-acp",
                groupTitle: "GitHub Copilot",
                baseURL: "https://api.githubcopilot.com",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: false,
                usesExternalAuth: true
            ),
            .init(
                slug: "xai-oauth",
                groupTitle: "xAI Grok",
                baseURL: "https://api.x.ai/v1",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: false,
                usesExternalAuth: true
            ),
            .init(
                slug: "xai",
                groupTitle: "xAI Grok",
                baseURL: "https://api.x.ai/v1",
                apiKeyEnv: "XAI_API_KEY",
                baseURLEnv: "XAI_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            ),
            .init(
                slug: "anthropic",
                groupTitle: "Anthropic",
                baseURL: "https://api.anthropic.com",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: false,
                usesExternalAuth: true
            ),
            .init(
                slug: "nous",
                groupTitle: "Nous Portal",
                baseURL: "https://inference-api.nousresearch.com/v1",
                apiKeyEnv: "",
                baseURLEnv: "",
                isKeyless: false,
                usesExternalAuth: true
            ),
            .init(
                slug: "gemini",
                groupTitle: "Google Gemini",
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKeyEnv: "GEMINI_API_KEY",
                baseURLEnv: "GEMINI_BASE_URL",
                isKeyless: false,
                usesExternalAuth: false
            )
        ]
        return Dictionary(uniqueKeysWithValues: items.map { ($0.slug, $0) })
    }()

    static func descriptor(for slug: String) -> HermesProviderDescriptor? {
        descriptors[slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    static func slug(forEndpoint rawValue: String) -> String {
        let host = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() ?? ""
        if host.contains("deepseek") {
            return "deepseek"
        }
        if host.contains("openrouter") {
            return "openrouter"
        }
        if host.contains("opencode.ai") {
            if rawValue.contains("/go/") {
                return "opencode-go"
            }
            return "opencode-free"
        }
        if host.contains("githubcopilot") || host.contains("copilot") {
            return "copilot"
        }
        if host == "api.x.ai" || host.hasSuffix(".x.ai") {
            return "xai-oauth"
        }
        if host.contains("openai.com") {
            return "openai-api"
        }
        if host.contains("anthropic") {
            return "anthropic"
        }
        if host.contains("nousresearch") {
            return "nous"
        }
        if host.contains("googleapis.com") {
            return "gemini"
        }
        return ""
    }

    static func groupTitle(forSlug slug: String, endpoint: String = "", isFree: Bool = false) -> String {
        if let title = descriptor(for: slug)?.groupTitle {
            return title
        }
        if isFree || slug == "opencode-free" {
            return "OpenCode"
        }
        return AIModelOption.providerTitle(for: endpoint, isFree: isFree)
    }

    private static let ambientCredentialSources: Set<String> = [
        "gh_cli",
        "claude_code",
        "qwen-cli"
    ]

    static func explicitlyConfiguredSlugs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
    ) -> Set<String> {
        var slugs: Set<String> = []
        slugs.formUnion(slugsFromAuth(at: homeDirectory.appendingPathComponent("auth.json")))
        slugs.formUnion(slugsFromConfig(at: homeDirectory.appendingPathComponent("config.yaml")))
        slugs.formUnion(
            slugsFromConfig(
                at: homeDirectory
                    .appendingPathComponent("profiles")
                    .appendingPathComponent(HermesAdapter.profileName)
                    .appendingPathComponent("config.yaml")
            )
        )
        slugs.formUnion(slugsFromEnv(at: homeDirectory.appendingPathComponent(".env")))
        slugs.formUnion(
            slugsFromEnv(
                at: homeDirectory
                    .appendingPathComponent("profiles")
                    .appendingPathComponent(HermesAdapter.profileName)
                    .appendingPathComponent(".env")
            )
        )
        return slugs
    }

    static func usableConfiguredSlugs(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
    ) -> Set<String> {
        let authURL = homeDirectory.appendingPathComponent("auth.json")
        let envURL = homeDirectory.appendingPathComponent(".env")
        let profileEnvURL = homeDirectory
            .appendingPathComponent("profiles")
            .appendingPathComponent(HermesAdapter.profileName)
            .appendingPathComponent(".env")
        let credentialed = slugsFromAuth(at: authURL)
            .union(slugsFromEnv(at: envURL))
            .union(slugsFromEnv(at: profileEnvURL))
        return Set(credentialed.filter { descriptor(for: $0) != nil })
    }

    static func hasUsableCredentials(
        for slug: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
    ) -> Bool {
        usableConfiguredSlugs(homeDirectory: homeDirectory).contains(
            slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    static func slugsFromAuth(at url: URL) -> Set<String> {
        guard let data = FileManager.default.contents(atPath: url.path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }
        return slugsFromAuthDocument(root)
    }

    static func slugsFromAuthDocument(_ root: [String: Any]) -> Set<String> {
        var slugs: Set<String> = []
        if let active = (root["active_provider"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !active.isEmpty
        {
            slugs.insert(active)
        }
        if let providers = root["providers"] as? [String: Any] {
            for key in providers.keys {
                let slug = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !slug.isEmpty {
                    slugs.insert(slug)
                }
            }
        }
        if let pool = root["credential_pool"] as? [String: Any] {
            for (key, value) in pool {
                let slug = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !slug.isEmpty else { continue }
                let entries = value as? [[String: Any]] ?? []
                if entries.contains(where: isExplicitCredential) {
                    slugs.insert(slug)
                }
            }
        }
        return slugs
    }

    static func isExplicitCredential(_ entry: [String: Any]) -> Bool {
        let source = (entry["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !source.isEmpty else { return false }
        if Self.ambientCredentialSources.contains(source) {
            return false
        }
        if source.hasPrefix("env:") {
            return true
        }
        if source.hasPrefix("manual:") {
            return true
        }
        return ["device_code", "loopback_pkce", "hermes_pkce", "manual"].contains(source)
    }

    private static func slugsFromConfig(at url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let mapping = HermesYAML.parseModelMapping(from: text)
        let slug = (mapping["provider"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return slug.isEmpty ? [] : [slug]
    }

    private static func slugsFromEnv(at url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let env = HermesEnvFile.parse(text)
        var slugs: Set<String> = []
        for descriptor in descriptors.values {
            let key = descriptor.apiKeyEnv
            guard !key.isEmpty else { continue }
            let value = (env[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if descriptor.slug == "openai-api" || descriptor.slug == "openai" {
                let base = (env[descriptor.baseURLEnv] ?? "").lowercased()
                if base.contains("deepseek") {
                    continue
                }
            }
            slugs.insert(descriptor.slug)
        }
        return slugs
    }

    static func loadCachedModels(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes")
    ) -> [String: [String]] {
        let files = [
            homeDirectory
                .appendingPathComponent("profiles")
                .appendingPathComponent(HermesAdapter.profileName)
                .appendingPathComponent("provider_models_cache.json"),
            homeDirectory.appendingPathComponent("provider_models_cache.json")
        ]
        var merged: [String: [String]] = [:]
        for file in files {
            guard let data = FileManager.default.contents(atPath: file.path) else { continue }
            for (slug, models) in modelsByProvider(from: data) where merged[slug] == nil {
                merged[slug] = models
            }
        }
        return merged
    }

    static func modelsByProvider(from data: Data) -> [String: [String]] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        var result: [String: [String]] = [:]
        for (slug, value) in root {
            let trimmedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmedSlug.isEmpty else { continue }
            let models: [String]
            if let entry = value as? [String: Any] {
                models = uniqueModels(entry["models"] as? [String] ?? [])
            } else if let list = value as? [String] {
                models = uniqueModels(list)
            } else {
                continue
            }
            if !models.isEmpty {
                result[trimmedSlug] = models
            }
        }
        return result
    }

    private static func uniqueModels(_ identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for identifier in identifiers {
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
