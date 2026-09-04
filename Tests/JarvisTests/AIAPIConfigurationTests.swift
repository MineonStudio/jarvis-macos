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
        let keylessFree = AIAPIConfiguration(
            endpoint: HermesFreeModelCatalog.endpoint,
            model: "laguna-s-2.1-free",
            apiKey: ""
        )

        XCTAssertFalse(missingKey.isConfigured)
        XCTAssertTrue(configured.isConfigured)
        XCTAssertTrue(keylessFree.isKeyless)
        XCTAssertTrue(keylessFree.isConfigured)
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

    func testMigrateDoesNotTreatOpenCodeAsProvider() throws {
        let suiteName = "AIAPIOpenCodeMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(HermesFreeModelCatalog.endpoint, forKey: AIAPIConfiguration.endpointKey)
        defaults.set("laguna-s-2.1-free", forKey: AIAPIConfiguration.modelKey)
        AIAPIConfiguration.migrateLegacyKeys(defaults: defaults)

        XCTAssertNil(defaults.string(forKey: AIAPIConfiguration.apiEndpointKey))
        XCTAssertFalse(AIAPIConfiguration.hasStoredAPIEndpoint(defaults: defaults))
        XCTAssertEqual(
            AIAPIConfiguration.loadProvider(defaults: defaults, resolvedAPIKey: "sk-deepseek").endpoint,
            AIAPIConfiguration.defaultEndpoint
        )
    }

    func testLoadProviderPrefersPaidEndpointWhenConversationIsFree() throws {
        let suiteName = "AIAPIPaidFallback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://api.deepseek.com/v1/chat/completions", forKey: AIAPIConfiguration.paidEndpointKey)
        defaults.set("deepseek-v4-flash", forKey: AIAPIConfiguration.paidModelKey)
        defaults.set(HermesFreeModelCatalog.endpoint, forKey: AIAPIConfiguration.endpointKey)
        defaults.set("laguna-s-2.1-free", forKey: AIAPIConfiguration.modelKey)

        let provider = AIAPIConfiguration.loadProvider(defaults: defaults, resolvedAPIKey: "sk-deepseek")
        XCTAssertEqual(provider.endpoint, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(provider.model, "deepseek-v4-flash")
        XCTAssertFalse(provider.isKeyless)
    }

    func testCombineDropsFreeNamesFromConfiguredProviderSection() {
        let options = AIModelOption.combine(
            paidModels: ["deepseek-v4-flash", "laguna-s-2.1-free"],
            paidEndpoint: "https://api.deepseek.com/v1/chat/completions",
            freeModels: ["laguna-s-2.1-free"]
        )
        XCTAssertEqual(options.filter { !$0.isFree }.map(\.model), ["deepseek-v4-flash"])
        XCTAssertTrue(options.filter(\.isFree).isEmpty)
    }

    func testJarvisAPIIgnoresConversationFreeEndpointKeys() throws {
        let suiteName = "AIAPIProviderConversationSplit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("https://api.deepseek.com/v1/chat/completions", forKey: AIAPIConfiguration.apiEndpointKey)
        defaults.set("deepseek-v4-flash", forKey: AIAPIConfiguration.apiModelKey)
        defaults.set(HermesFreeModelCatalog.endpoint, forKey: AIAPIConfiguration.endpointKey)
        defaults.set("laguna-s-2.1-free", forKey: AIAPIConfiguration.modelKey)

        let provider = AIAPIConfiguration.load(defaults: defaults, resolvedAPIKey: "sk-deepseek")
        XCTAssertEqual(provider.endpoint, "https://api.deepseek.com/v1/chat/completions")
        XCTAssertEqual(provider.model, "deepseek-v4-flash")
        XCTAssertEqual(provider.apiKey, "sk-deepseek")
        XCTAssertFalse(provider.isKeyless)
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
        XCTAssertEqual(deepSeekHost.openAIBaseURL, "https://api.deepseek.com/v1")
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
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedModelsURL(from: "https://api.deepseek.com/v1/chat/completions")?.absoluteString,
            "https://api.deepseek.com/v1/models"
        )
        XCTAssertEqual(
            OpenAICompatibleAPIClient.normalizedModelsURL(from: HermesFreeModelCatalog.endpoint)?.absoluteString,
            "https://opencode.ai/zen/v1/models"
        )
    }

    func testModelIdentifiersReadOpenAICompatibleDataArray() throws {
        let data = Data(#"{"data":[{"id":"deepseek-chat"},{"id":"deepseek-v4-flash"}]}"#.utf8)
        XCTAssertEqual(
            try OpenAICompatibleAPIClient.modelIdentifiers(from: data),
            ["deepseek-chat", "deepseek-v4-flash"]
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
