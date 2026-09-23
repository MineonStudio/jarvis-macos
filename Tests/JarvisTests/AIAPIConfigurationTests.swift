@testable import Jarvis
import XCTest

final class AIAPIConfigurationTests: XCTestCase {
    func testConfigurationRequiresEndpointModelAndAPIKey() {
        let missingKey = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: ""
        )
        let configured = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key"
        )
        XCTAssertFalse(missingKey.isConfigured)
        XCTAssertTrue(configured.isConfigured)
    }

    func testLoadUsesDefaultsWithoutStoredProviderValues() throws {
        let suiteName = "AIAPIConfigurationDefaults.(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let configuration = AIAPIConfiguration.load(defaults: defaults, resolvedAPIKey: nil)

        XCTAssertEqual(configuration.endpoint, AIAPIConfiguration.defaultEndpoint)
        XCTAssertEqual(configuration.model, AIAPIConfiguration.defaultModel)
        XCTAssertEqual(configuration.apiKey, "")
        XCTAssertFalse(AIAPIConfiguration.hasStoredAPIEndpoint(defaults: defaults))
    }

    func testRemoveStoredConfigurationClearsCurrentAndLegacyValues() throws {
        let suiteName = "AIAPIConfigurationRemove.(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keys = [
            AIAPIConfiguration.apiEndpointKey,
            AIAPIConfiguration.apiModelKey,
            AIAPIConfiguration.apiNameKey,
            AIAPIConfiguration.apiProviderKey,
            AIAPIConfiguration.endpointKey,
            AIAPIConfiguration.modelKey,
            AIAPIConfiguration.providerEndpointKey,
            AIAPIConfiguration.paidEndpointKey,
            AIAPIConfiguration.paidModelKey,
            AIAPIConfiguration.legacyEndpointKey,
            AIAPIConfiguration.legacyModelKey
        ]
        for key in keys {
            defaults.set("stored", forKey: key)
        }

        AIAPIConfiguration.removeStoredConfiguration(defaults: defaults)

        for key in keys {
            XCTAssertNil(defaults.object(forKey: key), "Expected (key) to be removed")
        }
        XCTAssertFalse(AIAPIConfiguration.hasStoredAPIEndpoint(defaults: defaults))
    }

    func testLoadPrefersNewKeysAndFallsBackToLegacyScreenshotKeys() throws {
        let suiteName = "AIAPIConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://legacy.example/v1/chat/completions", forKey: AIAPIConfiguration.legacyEndpointKey)
        defaults.set("legacy-model", forKey: AIAPIConfiguration.legacyModelKey)

        let fromLegacy = AIAPIConfiguration.load(defaults: defaults, resolvedAPIKey: "legacy-key")
        XCTAssertEqual(fromLegacy.endpoint, "https://legacy.example/v1/chat/completions")
        XCTAssertEqual(fromLegacy.model, "legacy-model")
        XCTAssertEqual(fromLegacy.apiKey, "legacy-key")

        defaults.set("https://new.example/v1/chat/completions", forKey: AIAPIConfiguration.endpointKey)
        defaults.set("new-model", forKey: AIAPIConfiguration.modelKey)
        let fromNew = AIAPIConfiguration.load(defaults: defaults, resolvedAPIKey: "new-key")
        XCTAssertEqual(fromNew.endpoint, "https://new.example/v1/chat/completions")
        XCTAssertEqual(fromNew.model, "new-model")
    }

    func testLoadProviderPrefersTheDedicatedProviderEndpoint() throws {
        let suiteName = "AIAPIPaidFallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://api.deepseek.com/v1/chat/completions", forKey: AIAPIConfiguration.paidEndpointKey)
        defaults.set("deepseek-v4-flash", forKey: AIAPIConfiguration.paidModelKey)
        defaults.set("https://legacy.example/v1/chat/completions", forKey: AIAPIConfiguration.endpointKey)
        defaults.set("legacy-model", forKey: AIAPIConfiguration.modelKey)

        let provider = AIAPIConfiguration.loadProvider(defaults: defaults, resolvedAPIKey: "sk-deepseek")
        XCTAssertEqual(provider.endpoint, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(provider.model, "deepseek-v4-flash")
        XCTAssertEqual(provider.apiKey, "sk-deepseek")
    }

    func testMigrateLegacyKeysWritesSharedAIKeysOnce() throws {
        let suiteName = "AIAPIConfigurationMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://legacy.example/v1/chat/completions", forKey: AIAPIConfiguration.legacyEndpointKey)
        defaults.set("legacy-model", forKey: AIAPIConfiguration.legacyModelKey)
        AIAPIConfiguration.migrateLegacyKeys(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AIAPIConfiguration.apiEndpointKey),
            "https://legacy.example/v1/chat/completions"
        )
        XCTAssertEqual(defaults.string(forKey: AIAPIConfiguration.apiModelKey), "legacy-model")
        XCTAssertEqual(
            defaults.string(forKey: AIAPIConfiguration.apiProviderKey),
            AIAPIProvider.custom.rawValue
        )

        defaults.set("https://new.example/v1/chat/completions", forKey: AIAPIConfiguration.apiEndpointKey)
        AIAPIConfiguration.migrateLegacyKeys(defaults: defaults)
        XCTAssertEqual(
            defaults.string(forKey: AIAPIConfiguration.apiEndpointKey),
            "https://new.example/v1/chat/completions"
        )
    }

    func testOpenAIBaseURLStripsChatCompletionsSuffix() {
        let configuration = AIAPIConfiguration(
            endpoint: "https://api.openai.com/v1/chat/completions/",
            model: "gpt-4o-mini",
            apiKey: "test-key"
        )
        XCTAssertEqual(configuration.openAIBaseURL, "https://api.openai.com/v1")

        let alreadyBase = AIAPIConfiguration(
            endpoint: "https://openrouter.ai/api/v1",
            model: "test",
            apiKey: "test-key"
        )
        XCTAssertEqual(alreadyBase.openAIBaseURL, "https://openrouter.ai/api/v1")

        let deepSeekHost = AIAPIConfiguration(
            endpoint: "https://api.deepseek.com",
            model: "deepseek-chat",
            apiKey: "test-key"
        )
        XCTAssertEqual(deepSeekHost.openAIBaseURL, "https://api.deepseek.com")
    }

    func testAPIConnectionTestRejectsMissingConfigurationBeforeNetworkCall() async {
        do {
            try await OpenAICompatibleAPIClient().testConnection(
                configuration: AIAPIConfiguration(endpoint: "", model: "", apiKey: "")
            )
            XCTFail("Expected missing configuration error")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .missingConfiguration)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIConnectionTestRejectsMalformedEndpointBeforeNetworkCall() async {
        do {
            try await OpenAICompatibleAPIClient().testConnection(
                configuration: AIAPIConfiguration(
                    endpoint: "not an endpoint",
                    model: "test-model",
                    apiKey: "test-key"
                )
            )
            XCTFail("Expected invalid endpoint error")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .invalidEndpoint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await OpenAICompatibleAPIClient().testConnection(
                configuration: AIAPIConfiguration(
                    endpoint: "http://api.openai.com/v1",
                    model: "test-model",
                    apiKey: "test-key"
                )
            )
            XCTFail("Expected invalid endpoint error")
        } catch let error as AIAPIError {
            XCTAssertEqual(error, .invalidEndpoint)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAPIConnectionTestRejectsEnvelopeWithoutTextContent() throws {
        let response: [String: Any] = [
            "choices": [[
                "message": [
                    "role": "assistant",
                    "content": NSNull()
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: response)

        XCTAssertThrowsError(try OpenAICompatibleAPIClient.validateConnectionEnvelope(from: data))
    }

    func testNormalizedEndpointRequiresHTTPSAndFillsOpenAICompletionsPath() {
        XCTAssertNil(OpenAICompatibleAPIClient.normalizedEndpointURL(from: "http://api.openai.com/v1"))
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "https://api.openai.com")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "https://api.openai.com/v1")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(from: "https://example.com/v1/chat/completions")?.absoluteString,
            "https://example.com/v1/chat/completions"
        )
    }

    func testProviderCatalogOffersPresetsAndRegionalBaseURLs() {
        XCTAssertTrue(AIAPIProvider.allCases.contains(.openAI))
        XCTAssertTrue(AIAPIProvider.allCases.contains(.deepSeek))
        XCTAssertTrue(AIAPIProvider.allCases.contains(.googleGemini))
        XCTAssertTrue(AIAPIProvider.allCases.contains(.doubao))
        XCTAssertTrue(AIAPIProvider.allCases.contains(.custom))
        for provider in AIAPIProvider.allCases where provider != .custom {
            XCTAssertNotNil(provider.brandIconResource, "Missing brand icon for \(provider.title)")
        }
        XCTAssertEqual(AIAPIProvider.dashScope.baseURLs.count, 3)
        XCTAssertEqual(AIAPIProvider.zhipu.baseURLs.count, 2)
        XCTAssertEqual(AIAPIProvider.deepSeek.defaultBaseURL, "https://api.deepseek.com")
        XCTAssertEqual(AIAPIProvider.doubao.defaultBaseURL, "https://ark.cn-beijing.volces.com/api/v3")
    }

    func testProviderDetectionAndProviderSpecificEndpointPaths() {
        XCTAssertEqual(AIAPIProvider.detect(endpoint: "https://api.deepseek.com"), .deepSeek)
        XCTAssertEqual(AIAPIProvider.detect(endpoint: "https://api.groq.com/openai/v1"), .groq)
        XCTAssertEqual(AIAPIProvider.detect(endpoint: "https://ark.cn-beijing.volces.com/api/v3"), .doubao)
        XCTAssertEqual(AIAPIProvider.detect(endpoint: "https://unknown.example/v1"), .custom)
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedEndpointURL(
                from: "https://api.deepseek.com",
                provider: .deepSeek
            )?.absoluteString,
            "https://api.deepseek.com/chat/completions"
        )
    }

    func testModelListURLAndResponseParserUseOpenAICompatibleShape() throws {
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedModelsURL(
                from: "https://api.openai.com/v1",
                provider: .openAI
            )?.absoluteString,
            "https://api.openai.com/v1/models"
        )
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedModelsURL(
                from: "https://api.deepseek.com",
                provider: .deepSeek
            )?.absoluteString,
            "https://api.deepseek.com/models"
        )

        let response: [String: Any] = [
            "data": [
                ["id": "model-z"],
                ["id": "model-a"],
                ["id": " model-a "],
                ["object": "model"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: response)
        XCTAssertEqual(
            try OpenAICompatibleAPIClient.modelIdentifiers(from: data),
            ["model-a", "model-z"]
        )
    }

    func testJSONContentExtractorAcceptsFencedObjectsAndRejectsProse() {
        let fenced = """
        ```json
        {"quote":"hello"}
        ```
        """
        let data = OpenAICompatibleAPIClient.jsonData(fromModelContent: fenced)
        XCTAssertNotNil(data)
        XCTAssertNil(OpenAICompatibleAPIClient.jsonData(fromModelContent: "not json"))
    }
}
