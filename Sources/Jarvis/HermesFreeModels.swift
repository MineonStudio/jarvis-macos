import Foundation

struct AIModelOption: Identifiable, Hashable, Sendable {
    var model: String
    var isFree: Bool
    var providerTitle: String
    var endpoint: String
    var hermesProvider: String = ""

    var id: String {
        let provider = hermesProvider.isEmpty ? providerTitle : hermesProvider
        return "\(provider)|\(model)"
    }

    var menuTitle: String {
        isFree ? "\(model)  free" : model
    }

    static func providerTitle(for endpoint: String, isFree: Bool) -> String {
        let slug = HermesProviderCatalog.slug(forEndpoint: endpoint)
        if !slug.isEmpty {
            return HermesProviderCatalog.groupTitle(forSlug: slug, endpoint: endpoint, isFree: isFree)
        }
        if isFree {
            return "OpenCode"
        }
        let host = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() ?? ""
        if host.contains("deepseek") {
            return "DeepSeek"
        }
        if host.contains("openrouter") {
            return "OpenRouter"
        }
        if host.contains("openai.com") || host == "api.openai.com" {
            return "OpenAI"
        }
        if host.contains("opencode.ai") {
            return "OpenCode"
        }
        return "已配置"
    }

    static func combine(
        paidModels: [String],
        paidEndpoint: String,
        freeModels: [String] = [],
        cache: [String: [String]] = [:],
        allowedSlugs: Set<String>? = nil,
        paidTitle: String = ""
    ) -> [AIModelOption] {
        _ = freeModels
        let paidSlug = HermesProviderCatalog.slug(forEndpoint: paidEndpoint)
        var merged = cache
        merged.removeValue(forKey: "opencode-free")
        if let allowedSlugs {
            var keep = allowedSlugs
            keep.remove("opencode-free")
            if !paidSlug.isEmpty {
                keep.insert(paidSlug)
            }
            merged = merged.filter { keep.contains($0.key) }
        }
        if paidSlug == "deepseek" {
            merged.removeValue(forKey: "openai-api")
            merged.removeValue(forKey: "openai")
        }

        if !paidEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !paidSlug.isEmpty {
            var models = merged[paidSlug] ?? []
            for model in paidModels.reversed() {
                let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !HermesFreeModelCatalog.isAnonymousFreeModel(trimmed) else {
                    continue
                }
                if let index = models.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    models.remove(at: index)
                }
                models.insert(trimmed, at: 0)
            }
            merged[paidSlug] = models
        }

        var options: [AIModelOption] = []
        var seen: Set<String> = []
        for slug in orderedSlugs(Array(merged.keys), paidSlug: paidSlug) {
            let descriptor = HermesProviderCatalog.descriptor(for: slug)
            let inferredTitle = HermesProviderCatalog.groupTitle(
                forSlug: slug,
                endpoint: slug == paidSlug ? paidEndpoint : descriptor?.chatCompletionsURL ?? ""
            )
            let title = slug == paidSlug && !paidTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? paidTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                : inferredTitle
            let endpoint = slug == paidSlug && !paidEndpoint.isEmpty
                ? paidEndpoint
                : descriptor?.chatCompletionsURL ?? ""
            let isKeyless = false
            for model in merged[slug] ?? [] {
                let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if !isKeyless, HermesFreeModelCatalog.isAnonymousFreeModel(trimmed) {
                    continue
                }
                let option = AIModelOption(
                    model: trimmed,
                    isFree: isKeyless || HermesFreeModelCatalog.isAnonymousFreeModel(trimmed),
                    providerTitle: title,
                    endpoint: endpoint,
                    hermesProvider: slug
                )
                if seen.insert(option.id).inserted {
                    options.append(option)
                }
            }
        }
        return options
    }

    private static func orderedSlugs(_ slugs: [String], paidSlug: String) -> [String] {
        slugs.sorted { lhs, rhs in
            if lhs == paidSlug, rhs != paidSlug {
                return true
            }
            if rhs == paidSlug, lhs != paidSlug {
                return false
            }
            if lhs == "opencode-free" {
                return false
            }
            if rhs == "opencode-free" {
                return true
            }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}

enum HermesFreeModelCatalog {
    static let endpoint = "https://opencode.ai/zen/v1/chat/completions"
    static let modelsURL = URL(string: "https://opencode.ai/zen/v1/models")
    static let catalogURL = URL(string: "https://hermes-agent.nousresearch.com/docs/api/model-catalog.json")

    static let floor = [
        "deepseek-v4-flash-free",
        "hy3-free",
        "mimo-v2.5-free",
        "laguna-s-2.1-free",
        "nemotron-3-ultra-free",
        "nemotron-3.5-lightning-free",
        "muse-spark-1.2-contributor-free",
        "muse-spark-1.3-contributor-free"
    ]

    private static let keyedFreeExclusions: Set<String> = [
        "ox-alpha-free"
    ]

    static func isAnonymousFreeModel(_ identifier: String) -> Bool {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return false }
        let lowered = id.lowercased()
        if keyedFreeExclusions.contains(lowered) {
            return false
        }
        if floor.contains(where: { $0.lowercased() == lowered }) {
            return true
        }
        if lowered.hasSuffix("-free") || lowered.hasSuffix(":free") {
            return true
        }
        return lowered == "big-pickle"
    }

    static func cachedIdentifiers(fromProviderCache data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root["opencode-free"] as? [String: Any],
              let models = entry["models"] as? [String]
        else {
            return []
        }
        return uniqueFree(models)
    }

    static func identifiers(fromModelsResponse data: Data) throws -> [String] {
        try uniqueFree(OpenAICompatibleAPIClient.modelIdentifiers(from: data))
    }

    static func identifiers(fromOpenRouterCatalog data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["providers"] as? [String: Any],
              let openrouter = providers["openrouter"] as? [String: Any],
              let models = openrouter["models"] as? [[String: Any]]
        else {
            return []
        }
        let identifiers = models.compactMap { item -> String? in
            let identifier = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = (item["description"] as? String)?.lowercased() ?? ""
            guard !identifier.isEmpty else { return nil }
            if description == "free" || isAnonymousFreeModel(identifier) {
                return identifier
            }
            return nil
        }
        return uniqueFree(identifiers)
    }

    static func loadCached(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".hermes")
    ) -> [String] {
        let files = [
            homeDirectory
                .appendingPathComponent("profiles")
                .appendingPathComponent(HermesAdapter.profileName)
                .appendingPathComponent("provider_models_cache.json"),
            homeDirectory.appendingPathComponent("provider_models_cache.json")
        ]
        for file in files {
            guard let data = FileManager.default.contents(atPath: file.path) else { continue }
            let models = cachedIdentifiers(fromProviderCache: data)
            if !models.isEmpty {
                return models
            }
        }
        return floor
    }

    static func fetchLive() async -> [String] {
        guard let modelsURL else { return [] }
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("https://hermes-agent.nousresearch.com", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Jarvis", forHTTPHeaderField: "X-Title")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return []
            }
            return try identifiers(fromModelsResponse: data)
        } catch {
            return []
        }
    }

    static func mergedFreeModels(cached: [String], live: [String]) -> [String] {
        uniqueFree(live + cached + floor)
    }

    private static func uniqueFree(_ identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for identifier in identifiers {
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isAnonymousFreeModel(trimmed) else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }
}
