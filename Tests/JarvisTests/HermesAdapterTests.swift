@testable import Jarvis
import XCTest

final class HermesAdapterTests: XCTestCase {
    func testAgentLogParserSurfacesToolAndRateLimitStatus() {
        XCTAssertEqual(
            HermesAgentLogParser.status(
                from: "2026-09-04 12:21:31 INFO [abc] agent.turn_context: conversation turn: session=s model=mimo-v2.5-free provider=opencode-free platform=cli history=2 msg='hi'"
            ),
            "正在用 OpenCode（mimo-v2.5-free）思考"
        )
        XCTAssertEqual(
            HermesAgentLogParser.status(from: "tool read_file completed (0.40s, 12 chars)"),
            "已完成：读取文件"
        )
        XCTAssertEqual(
            HermesAgentLogParser.status(
                from: "HTTP 429: Error from provider (Console): Rate limit exceeded."
            ),
            "免费额度已用完，正在重试…"
        )
        XCTAssertEqual(
            HermesAgentLogParser.failureReason(
                stderr: "↻ Resumed session abc\nModel restored from session: deepseek-v4-flash (deepseek)\n\nsession_id: abc",
                log: "API call failed after 3 retries. HTTP 429: FreeUsageLimitError"
            ),
            "免费模型额度已用完，请稍后再试或换成 DeepSeek / xAI"
        )
    }

    func testChatPayloadPutsFilesInQueryAndImagesOnCLI() {
        let file = HermesChatAttachment(
            kind: .file,
            fileURL: URL(fileURLWithPath: "/tmp/notes.md"),
            displayName: "notes.md"
        )
        let image = HermesChatAttachment(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/shot.png"),
            displayName: "shot.png"
        )
        let extra = HermesChatAttachment(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/shot2.png"),
            displayName: "shot2.png"
        )
        let link = HermesChatAttachment(
            kind: .url,
            remoteURL: "https://example.com/a",
            displayName: "example.com"
        )
        let payload = HermesChatPayload.compose(
            draft: "看看这些",
            attachments: [file, image, extra, link]
        )
        XCTAssertEqual(payload.imagePaths, ["/tmp/shot.png", "/tmp/shot2.png"])
        XCTAssertTrue(payload.query.contains("看看这些"))
        XCTAssertTrue(payload.query.contains("用户附加了文件：/tmp/notes.md"))
        XCTAssertTrue(payload.query.contains("用户附加了图片：/tmp/shot2.png"))
        XCTAssertTrue(payload.query.contains("用户附加了链接：https://example.com/a"))
        XCTAssertFalse(payload.query.contains("用户附加了图片：/tmp/shot.png"))
        XCTAssertEqual(payload.displayText, "看看这些")
        XCTAssertEqual(payload.attachmentNames, ["notes.md", "shot.png", "shot2.png", "example.com"])
    }

    func testChatPayloadAllowsImageOnlySend() {
        let image = HermesChatAttachment(
            kind: .image,
            fileURL: URL(fileURLWithPath: "/tmp/only.png"),
            displayName: "only.png"
        )
        let payload = HermesChatPayload.compose(draft: "  ", attachments: [image])
        XCTAssertEqual(payload.imagePaths, ["/tmp/only.png"])
        XCTAssertEqual(payload.query, "[User attached image: only.png]")
        XCTAssertEqual(payload.displayText, "only.png")
    }

    func testEnvUpsertPreservesUnrelatedKeysAndQuotesUnsafeValues() {
        let original = """
        TELEGRAM_BOT_TOKEN=abc
        OPENAI_API_KEY=old
        """
        let updated = HermesEnvFile.upsert(
            [
                "OPENAI_API_KEY": "sk test",
                "OPENAI_BASE_URL": "https://api.openai.com/v1"
            ],
            into: original
        )
        let parsed = HermesEnvFile.parse(updated)
        XCTAssertEqual(parsed["TELEGRAM_BOT_TOKEN"], "abc")
        XCTAssertEqual(parsed["OPENAI_API_KEY"], "sk test")
        XCTAssertEqual(parsed["OPENAI_BASE_URL"], "https://api.openai.com/v1")
        XCTAssertTrue(updated.contains("OPENAI_API_KEY=\"sk test\""))
    }

    func testEnvRemovingKeysPreservesUnrelatedValues() {
        let original = """
        TELEGRAM_BOT_TOKEN=abc
        OPENAI_API_KEY=secret
        OPENAI_BASE_URL=https://api.openai.com/v1
        """

        let updated = HermesEnvFile.removing(
            keys: ["OPENAI_API_KEY", "OPENAI_BASE_URL"],
            from: original
        )

        let parsed = HermesEnvFile.parse(updated)
        XCTAssertEqual(parsed["TELEGRAM_BOT_TOKEN"], "abc")
        XCTAssertNil(parsed["OPENAI_API_KEY"])
        XCTAssertNil(parsed["OPENAI_BASE_URL"])
    }

    func testYAMLUpsertReplacesEmptyModelSentinelAndKeepsOtherSections() {
        let original = """
        model: ""
        terminal:
          backend: local
        """
        let updated = HermesYAML.upsertModel(
            in: original,
            mapping: HermesYAML.ModelMapping(
                provider: "openai",
                model: "gpt-4o-mini",
                baseURL: "https://api.openai.com/v1",
                apiMode: "chat_completions"
            )
        )
        let mapping = HermesYAML.parseModelMapping(from: updated)
        XCTAssertEqual(mapping["provider"], "openai")
        XCTAssertEqual(mapping["default"], "gpt-4o-mini")
        XCTAssertEqual(mapping["base_url"], "https://api.openai.com/v1")
        XCTAssertTrue(updated.contains("terminal:"))
        XCTAssertTrue(updated.contains("backend: local"))
    }

    func testCreateProfileWritesIsolatedJarvisHomeAndDoesNotTouchDefaultSoul() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterTests.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        let defaultSoul = hermesHome.appendingPathComponent("SOUL.md")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: hermesHome, withIntermediateDirectories: true)
        try "default soul".write(to: defaultSoul, atomically: true, encoding: .utf8)

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()

        let status = adapter.inspect()
        XCTAssertTrue(status.homeExists)
        XCTAssertFalse(status.isInstalled)
        XCTAssertTrue(status.isProfileReady)
        XCTAssertTrue(FileManager.default.fileExists(atPath: adapter.soulURL.path))
        XCTAssertEqual(try String(contentsOf: defaultSoul, encoding: .utf8), "default soul")
        XCTAssertTrue(
            try String(contentsOf: adapter.soulURL, encoding: .utf8)
                .contains(HermesSoul.marker)
        )
        XCTAssertEqual(
            adapter.soulURL.path,
            hermesHome.appendingPathComponent("profiles/jarvis/SOUL.md").path
        )
    }

    func testSyncWritesOpenAICompatibleEnvAndModelThenImportReadsThemBack() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterSyncTests.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()
        try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: "https://example.com/v1/chat/completions",
                model: "local-model",
                apiKey: "secret-key"
            )
        )

        let env = try HermesEnvFile.parse(String(contentsOf: adapter.envURL, encoding: .utf8))
        XCTAssertEqual(env["OPENAI_API_KEY"], "secret-key")
        XCTAssertEqual(env["OPENAI_BASE_URL"], "https://example.com/v1")

        let mapping = try HermesYAML.parseModelMapping(
            from: String(contentsOf: adapter.configURL, encoding: .utf8)
        )
        XCTAssertEqual(mapping["provider"], "openai")
        XCTAssertEqual(mapping["default"], "local-model")
        XCTAssertEqual(mapping["base_url"], "https://example.com/v1")
        XCTAssertEqual(mapping["api_mode"], "chat_completions")

        let imported = try XCTUnwrap(adapter.importConfiguration())
        XCTAssertEqual(imported.apiKey, "secret-key")
        XCTAssertEqual(imported.model, "local-model")
        XCTAssertEqual(imported.endpoint, "https://example.com/v1/chat/completions")
        XCTAssertTrue(imported.isConfigured)
        XCTAssertTrue(adapter.inspect().hasAPIKey)
    }

    func testSyncWithoutProfileThrowsAndImportPrefersJarvisProfileOverDefaultHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterImportTests.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        XCTAssertThrowsError(try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: "https://example.com/v1/chat/completions",
                model: "x",
                apiKey: "y"
            )
        )) { error in
            XCTAssertEqual(error as? HermesError, .profileMissing)
        }

        try FileManager.default.createDirectory(at: hermesHome, withIntermediateDirectories: true)
        try HermesEnvFile.upsert(
            [
                "OPENAI_API_KEY": "default-key",
                "OPENAI_BASE_URL": "https://default.example/v1"
            ],
            into: ""
        ).write(
            to: hermesHome.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try adapter.createJarvisProfile()
        try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: "https://jarvis.example/v1/chat/completions",
                model: "jarvis-model",
                apiKey: "jarvis-key"
            )
        )

        let imported = try XCTUnwrap(adapter.importConfiguration())
        XCTAssertEqual(imported.apiKey, "jarvis-key")
        XCTAssertEqual(imported.model, "jarvis-model")
    }

    func testDeepSeekEndpointSyncsNativeProviderAndV1BaseURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterDeepSeekTests.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()
        try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: "https://api.deepseek.com",
                model: "deepseek-v4-flash",
                apiKey: "sk-deepseek"
            )
        )

        let env = try HermesEnvFile.parse(String(contentsOf: adapter.envURL, encoding: .utf8))
        XCTAssertEqual(env["DEEPSEEK_API_KEY"], "sk-deepseek")
        XCTAssertEqual(env["OPENAI_API_KEY"], "sk-deepseek")
        XCTAssertEqual(env["OPENAI_BASE_URL"], "https://api.deepseek.com/v1")

        let mapping = try HermesYAML.parseModelMapping(
            from: String(contentsOf: adapter.configURL, encoding: .utf8)
        )
        XCTAssertEqual(mapping["provider"], "deepseek")
        XCTAssertEqual(mapping["default"], "deepseek-v4-flash")
        XCTAssertEqual(mapping["base_url"], "https://api.deepseek.com/v1")
        XCTAssertFalse(
            try String(contentsOf: adapter.configURL, encoding: .utf8)
                .contains("default: 'deepseek-v4-flash'")
        )
        XCTAssertTrue(adapter.inspect().hasAPIKey)

        let imported = try XCTUnwrap(adapter.importConfiguration())
        XCTAssertEqual(imported.apiKey, "sk-deepseek")
        XCTAssertEqual(imported.model, "deepseek-v4-flash")
        XCTAssertEqual(imported.endpoint, "https://api.deepseek.com/v1/chat/completions")
    }

    func testImportReadsDeepSeekKeyFromDefaultHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterDefaultImport.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: hermesHome, withIntermediateDirectories: true)
        try HermesEnvFile.upsert(
            ["DEEPSEEK_API_KEY": "from-default"],
            into: ""
        ).write(to: hermesHome.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try HermesYAML.modelBlock(
            HermesYAML.ModelMapping(
                provider: "deepseek",
                model: "deepseek-chat",
                baseURL: "https://api.deepseek.com/v1",
                apiMode: "chat_completions"
            )
        ).write(to: hermesHome.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        let imported = try XCTUnwrap(adapter.importConfiguration())
        XCTAssertEqual(imported.apiKey, "from-default")
        XCTAssertEqual(imported.model, "deepseek-chat")
        XCTAssertEqual(imported.endpoint, "https://api.deepseek.com/v1/chat/completions")
    }

    func testProviderCacheParsesEveryHermesProviderBlock() {
        let cache = Data(#"""
        {
          "deepseek": {"models": ["deepseek-v4-flash"]},
          "copilot": {"models": ["gpt-5.5"]},
          "opencode-free": {"models": ["laguna-s-2.1-free"]}
        }
        """#.utf8)
        let parsed = HermesProviderCatalog.modelsByProvider(from: cache)
        XCTAssertEqual(parsed["deepseek"], ["deepseek-v4-flash"])
        XCTAssertEqual(parsed["copilot"], ["gpt-5.5"])
        XCTAssertEqual(parsed["opencode-free"], ["laguna-s-2.1-free"])
        XCTAssertEqual(
            HermesProviderCatalog.groupTitle(forSlug: "xai-oauth"),
            "xAI Grok"
        )
        XCTAssertEqual(
            HermesProviderCatalog.groupTitle(forSlug: "opencode-free"),
            "OpenCode"
        )
    }

    func testFreeCatalogParsesOpencodeCacheAndMarksAnonymousModels() {
        let cache = Data(#"""
        {"opencode-free":{"models":["deepseek-v4-flash-free","ox-alpha-free","laguna-s-2.1-free"]}}
        """#.utf8)
        XCTAssertEqual(
            HermesFreeModelCatalog.cachedIdentifiers(fromProviderCache: cache),
            ["deepseek-v4-flash-free", "laguna-s-2.1-free"]
        )
        XCTAssertTrue(HermesFreeModelCatalog.isAnonymousFreeModel("nemotron-3-ultra-free"))
        XCTAssertTrue(HermesFreeModelCatalog.isAnonymousFreeModel("z-ai/glm-5.2:free"))
        XCTAssertFalse(HermesFreeModelCatalog.isAnonymousFreeModel("ox-alpha-free"))
        XCTAssertEqual(
            AIModelOption(
                model: "laguna-s-2.1-free",
                isFree: true,
                providerTitle: "OpenCode",
                endpoint: HermesFreeModelCatalog.endpoint
            ).menuTitle,
            "laguna-s-2.1-free  free"
        )
    }

    func testModelOptionsGroupConfiguredProviderSeparatelyFromHermesFree() {
        let options = AIModelOption.combine(
            paidModels: ["deepseek-v4-flash", "deepseek-v4-pro"],
            paidEndpoint: "https://api.deepseek.com/v1/chat/completions",
            freeModels: ["laguna-s-2.1-free", "deepseek-v4-flash-free"]
        )
        XCTAssertEqual(
            options.filter { !$0.isFree }.map(\.providerTitle),
            ["DeepSeek", "DeepSeek"]
        )
        XCTAssertTrue(options.filter(\.isFree).isEmpty)
        XCTAssertEqual(
            options.first { $0.model == "deepseek-v4-flash" }?.endpoint,
            "https://api.deepseek.com/v1/chat/completions"
        )
        XCTAssertNil(options.first { $0.model == "laguna-s-2.1-free" })
        XCTAssertEqual(
            options.first { $0.model == "deepseek-v4-flash" }?.hermesProvider,
            "deepseek"
        )
    }

    func testModelOptionsMapHermesProviderCacheWithHermesGroupTitles() {
        let cache: [String: [String]] = [
            "deepseek": ["deepseek-v4-pro", "deepseek-v4-flash"],
            "openai-api": ["deepseek-v4-flash"],
            "copilot": ["gpt-5.5", "claude-opus-4.7"],
            "xai-oauth": ["grok-4.6"],
            "opencode-free": ["laguna-s-2.1-free"]
        ]
        let options = AIModelOption.combine(
            paidModels: ["deepseek-v4-flash"],
            paidEndpoint: "https://api.deepseek.com/v1/chat/completions",
            freeModels: ["muse-spark-1.3-contributor-free"],
            cache: cache,
            allowedSlugs: ["deepseek", "xai-oauth", "opencode-free"]
        )
        XCTAssertEqual(
            Set(options.map(\.providerTitle)),
            ["DeepSeek", "xAI Grok"]
        )
        XCTAssertNil(options.first { $0.hermesProvider == "openai-api" })
        XCTAssertNil(options.first { $0.hermesProvider == "copilot" })
        XCTAssertNil(options.first { $0.hermesProvider == "opencode-free" })
        XCTAssertEqual(
            options.first { $0.model == "grok-4.6" }?.providerTitle,
            "xAI Grok"
        )
    }

    func testUsableConfiguredSlugsIgnoreAutoProviderWithoutCredentials() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesUsableSlugs.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "model:\n  provider: auto\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)

        XCTAssertTrue(HermesProviderCatalog.usableConfiguredSlugs(homeDirectory: home).isEmpty)
        XCTAssertFalse(
            HermesProviderCatalog.hasUsableCredentials(for: "auto", homeDirectory: home)
        )
    }

    func testUsableConfiguredSlugsReadProfileAPIKey() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesUsableProfileSlugs.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let profile = home
            .appendingPathComponent("profiles")
            .appendingPathComponent(HermesAdapter.profileName)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try "DEEPSEEK_API_KEY=test-key\n"
            .write(to: profile.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        XCTAssertTrue(
            HermesProviderCatalog.hasUsableCredentials(
                for: "deepseek",
                homeDirectory: home
            )
        )
    }

    func testAmbientGitHubCLICredentialIsNotTreatedAsConfiguredCopilot() {
        let auth: [String: Any] = [
            "active_provider": "xai-oauth",
            "providers": ["xai-oauth": ["auth_mode": "oauth_device_code"]],
            "credential_pool": [
                "copilot": [[
                    "source": "gh_cli",
                    "label": "gh auth token"
                ]],
                "deepseek": [[
                    "source": "env:DEEPSEEK_API_KEY"
                ]],
                "xai-oauth": [[
                    "source": "device_code"
                ]]
            ]
        ]
        let slugs = HermesProviderCatalog.slugsFromAuthDocument(auth)
        XCTAssertEqual(slugs, ["xai-oauth", "deepseek"])
        XCTAssertFalse(slugs.contains("copilot"))
        XCTAssertFalse(
            HermesProviderCatalog.isExplicitCredential(["source": "gh_cli"])
        )
        XCTAssertTrue(
            HermesProviderCatalog.isExplicitCredential(["source": "device_code"])
        )
    }

    func testHermesBindingUsesExplicitProviderSlug() {
        let binding = HermesInferenceProvider.binding(
            for: AIAPIConfiguration(
                endpoint: "https://api.githubcopilot.com/chat/completions",
                model: "gpt-5.5",
                apiKey: "sk-deepseek"
            )
        )
        XCTAssertEqual(binding.provider, "copilot")
        XCTAssertEqual(binding.apiKeyEnv, "")
        XCTAssertEqual(binding.baseURL, "https://api.githubcopilot.com")
        XCTAssertEqual(binding.model, "gpt-5.5")
    }

    func testInjectAPIDoesNotOverwriteExistingEnvOrSelectedModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterInject.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()
        try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: "https://api.deepseek.com/v1/chat/completions",
                model: "deepseek-v4-flash",
                apiKey: "sk-old"
            )
        )
        try adapter.setCurrentModel(
            provider: "xai-oauth",
            model: "grok-4.3",
            baseURL: "https://api.x.ai/v1"
        )

        try adapter.injectAPIIfAbsent(
            AIAPIConfiguration(
                endpoint: "https://api.deepseek.com/v1/chat/completions",
                model: "deepseek-v4-pro",
                apiKey: "sk-new"
            )
        )

        let env = try HermesEnvFile.parse(String(contentsOf: adapter.envURL, encoding: .utf8))
        XCTAssertEqual(env["DEEPSEEK_API_KEY"], "sk-old")
        let current = try XCTUnwrap(adapter.currentModel())
        XCTAssertEqual(current.provider, "xai-oauth")
        XCTAssertEqual(current.model, "grok-4.3")
        XCTAssertFalse(current.isPlaceholder)
    }

    func testInjectAPIFillsPlaceholderProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterInjectPlaceholder.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()
        try adapter.injectAPIIfAbsent(
            AIAPIConfiguration(
                endpoint: "https://api.deepseek.com/v1/chat/completions",
                model: "deepseek-v4-flash",
                apiKey: "sk-deepseek"
            )
        )
        let env = try HermesEnvFile.parse(String(contentsOf: adapter.envURL, encoding: .utf8))
        XCTAssertEqual(env["DEEPSEEK_API_KEY"], "sk-deepseek")
        let current = try XCTUnwrap(adapter.currentModel())
        XCTAssertEqual(current.provider, "deepseek")
        XCTAssertEqual(current.model, "deepseek-v4-flash")
    }

    func testRemoveInjectedAPIConfigurationClearsSecretsAndResetsModel() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterRemoveAPI.(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()
        try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: "https://api.deepseek.com/v1/chat/completions",
                model: "deepseek-v4-flash",
                apiKey: "sk-deepseek"
            )
        )
        try HermesEnvFile.upsert(
            ["TELEGRAM_BOT_TOKEN": "keep-me"],
            into: String(contentsOf: adapter.envURL, encoding: .utf8)
        ).write(to: adapter.envURL, atomically: true, encoding: .utf8)

        try adapter.removeInjectedAPIConfiguration()

        let env = try HermesEnvFile.parse(String(contentsOf: adapter.envURL, encoding: .utf8))
        XCTAssertEqual(env["TELEGRAM_BOT_TOKEN"], "keep-me")
        XCTAssertNil(env["DEEPSEEK_API_KEY"])
        XCTAssertNil(env["OPENAI_API_KEY"])
        XCTAssertNil(env["OPENAI_BASE_URL"])
        XCTAssertFalse(adapter.inspect().hasAPIKey)
        XCTAssertTrue(try XCTUnwrap(adapter.currentModel()).isPlaceholder)
    }

    func testSyncingOpenCodeFreeModelWritesKeylessProvider() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterFreeModel.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        try adapter.createJarvisProfile()
        try adapter.sync(
            configuration: AIAPIConfiguration(
                endpoint: HermesFreeModelCatalog.endpoint,
                model: "laguna-s-2.1-free",
                apiKey: ""
            )
        )
        let mapping = try HermesYAML.parseModelMapping(
            from: String(contentsOf: adapter.configURL, encoding: .utf8)
        )
        XCTAssertEqual(mapping["provider"], "opencode-free")
        XCTAssertEqual(mapping["default"], "laguna-s-2.1-free")
        XCTAssertEqual(mapping["base_url"], "https://opencode.ai/zen/v1")
    }

    func testUserNameUpsertReplacesExistingNameLine() {
        let updated = HermesInferenceProvider.upsertUserName(
            "Tony",
            into: "# USER.md\n\n- Name:\n- Preferred language: 中文\n"
        )
        XCTAssertEqual(HermesInferenceProvider.parseUserName(from: updated), "Tony")
        XCTAssertTrue(updated.contains("- Preferred language: 中文"))
    }

    func testListBotsOnlyIncludesTheJarvisProfile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesAdapterListBots.\(UUID().uuidString)")
        let hermesHome = root.appendingPathComponent(".hermes")
        defer { try? FileManager.default.removeItem(at: root) }

        let adapter = HermesAdapter(
            homeDirectory: hermesHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        XCTAssertTrue(adapter.listBots().isEmpty)

        try FileManager.default.createDirectory(
            at: hermesHome.appendingPathComponent("profiles/other"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(adapter.listBots().isEmpty)

        try adapter.createJarvisProfile()
        let bots = adapter.listBots()
        XCTAssertEqual(bots.map(\.id), ["jarvis"])
        XCTAssertEqual(bots.first?.title, "JARVIS")
    }

    func testInspectReportsMissingInstallWhenHomeAndCLIAreAbsent() {
        let missingHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesMissing.\(UUID().uuidString)")
        let adapter = HermesAdapter(
            homeDirectory: missingHome,
            pathEnvironment: "",
            extraSearchPaths: []
        )
        let status = adapter.inspect()
        XCTAssertFalse(status.isInstalled)
        XCTAssertFalse(status.isProfileReady)
        XCTAssertTrue(status.message.contains("未检测到 Hermes"))
    }
}

final class HermesInstallerTests: XCTestCase {
    func testInstallerUsesTheOfficialScriptAndSurfacesTheLastOutputLine() {
        XCTAssertEqual(
            HermesInstaller.scriptURL.absoluteString,
            "https://hermes-agent.nousresearch.com/install.sh"
        )
        XCTAssertEqual(
            HermesInstaller.lastMeaningfulLine(
                in: "\u{001B}[32mInstalling Hermes\u{001B}[0m\n  finished  "
            ),
            "finished"
        )
    }

    func testInstallerErrorIncludesAReadableOutputTail() {
        let error = HermesInstallerError.failed(
            status: 12,
            output: "download started\n\u{001B}[31mnetwork unavailable\u{001B}[0m\n"
        )

        XCTAssertEqual(
            error.localizedDescription,
            "Hermes 安装程序未完成：network unavailable"
        )
    }

    func testTirithPreinstallUsesTheSynchronousHermesResolver() {
        XCTAssertTrue(HermesTirithInstaller.pythonScript.contains("_resolve_tirith_path"))
        XCTAssertTrue(HermesTirithInstaller.pythonScript.contains("Tirith ready"))
    }

    func testTirithInstallerErrorIncludesAReadableOutputTail() {
        let error = HermesSecurityInstallerError.failed(
            output: "download started\n\u{001B}[31mchecksum mismatch\u{001B}[0m\n"
        )

        XCTAssertEqual(
            error.localizedDescription,
            "Hermes 安全组件准备失败：checksum mismatch"
        )
    }
}

final class HermesUninstallerTests: XCTestCase {
    func testRemovesHermesHomeAndManagedLaunchersButKeepsUnrelatedFiles() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("HermesUninstaller.\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let hermesHome = home.appendingPathComponent(".hermes")
        let commandDirectory = home.appendingPathComponent(".local/bin")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(
            at: hermesHome.appendingPathComponent("profiles/jarvis"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: commandDirectory,
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexec \(hermesHome.path)/hermes-agent/venv/bin/python".write(
            to: commandDirectory.appendingPathComponent("hermes"),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.createSymbolicLink(
            at: commandDirectory.appendingPathComponent("node"),
            withDestinationURL: hermesHome.appendingPathComponent("node/bin/node")
        )
        try "keep me".write(
            to: commandDirectory.appendingPathComponent("python"),
            atomically: true,
            encoding: .utf8
        )

        try HermesUninstaller(
            fileManager: fileManager,
            homeDirectory: home,
            commandDirectories: [commandDirectory]
        ).uninstall()

        XCTAssertFalse(fileManager.fileExists(atPath: hermesHome.path))
        XCTAssertFalse(fileManager.fileExists(atPath: commandDirectory.appendingPathComponent("hermes").path))
        XCTAssertFalse(fileManager.fileExists(atPath: commandDirectory.appendingPathComponent("node").path))
        XCTAssertTrue(fileManager.fileExists(atPath: commandDirectory.appendingPathComponent("python").path))
    }

    func testDoesNotRemoveUnmanagedLauncherWithTheSameName() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("HermesUninstaller.\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let commandDirectory = home.appendingPathComponent(".local/bin")
        let launcher = commandDirectory.appendingPathComponent("hermes")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
        try "#!/bin/sh\nexec /opt/custom/hermes".write(
            to: launcher,
            atomically: true,
            encoding: .utf8
        )

        try HermesUninstaller(
            fileManager: fileManager,
            homeDirectory: home,
            commandDirectories: [commandDirectory]
        ).uninstall()

        XCTAssertTrue(fileManager.fileExists(atPath: launcher.path))
    }

    func testStandardUninstallRemovesRuntimeButKeepsHermesData() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("HermesUninstaller.\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let hermesHome = home.appendingPathComponent(".hermes")
        let commandDirectory = home.appendingPathComponent(".local/bin")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(
            at: hermesHome.appendingPathComponent("profiles/jarvis"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: hermesHome.appendingPathComponent("hermes-agent"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: hermesHome.appendingPathComponent("node"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: hermesHome.appendingPathComponent("bin"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
        try "runtime".write(
            to: hermesHome.appendingPathComponent("bin/uv"),
            atomically: true,
            encoding: .utf8
        )
        try "#!/bin/sh\nexec \(hermesHome.path)/hermes-agent/venv/bin/python".write(
            to: commandDirectory.appendingPathComponent("hermes"),
            atomically: true,
            encoding: .utf8
        )

        try HermesUninstaller(
            fileManager: fileManager,
            homeDirectory: home,
            commandDirectories: [commandDirectory]
        ).uninstall(mode: .standard)

        XCTAssertFalse(fileManager.fileExists(atPath: hermesHome.appendingPathComponent("hermes-agent").path))
        XCTAssertFalse(fileManager.fileExists(atPath: hermesHome.appendingPathComponent("node").path))
        XCTAssertFalse(fileManager.fileExists(atPath: hermesHome.appendingPathComponent("bin/uv").path))
        XCTAssertTrue(fileManager.fileExists(atPath: hermesHome.appendingPathComponent("profiles/jarvis").path))
        XCTAssertTrue(fileManager.fileExists(atPath: hermesHome.path))
    }
}
