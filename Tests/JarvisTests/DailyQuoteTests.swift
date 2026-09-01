@testable import Jarvis
import XCTest

final class DailyQuoteTests: XCTestCase {
    func testBuiltInQuoteAndDayKeyAreDeterministic() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))

        XCTAssertEqual(DailyQuote.dayKey(for: date, calendar: calendar), "2026-09-01")
        XCTAssertEqual(DailyQuote.builtIn(for: date, calendar: calendar).source, .builtIn)
        XCTAssertFalse(DailyQuote.builtIn(for: date, calendar: calendar).text.isEmpty)
    }

    func testStoreOnlyReturnsQuoteForTheRequestedDay() throws {
        let suiteName = "DailyQuoteTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = DailyQuoteStore(defaults: defaults)
        let quote = DailyQuote(text: "今天也要向前一步。", source: .builtIn)
        store.save(quote, for: "2026-09-01")

        XCTAssertEqual(store.load(for: "2026-09-01"), quote)
        XCTAssertNil(store.load(for: "2026-09-02"))
    }

    func testServiceParsesAIQuoteResponse() async throws {
        let service = DailyQuoteService(
            apiClient: StubDailyQuoteAPI(response: "```json\n{\"quote\":\"让每一次开始，都成为更好的方向。\"}\n```")
        )
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key"
        )

        let quote = try await service.generate(for: "2026-09-01", configuration: configuration)

        XCTAssertEqual(quote.text, "让每一次开始，都成为更好的方向。")
        XCTAssertEqual(quote.source, .ai)
    }

    func testServiceRejectsMalformedAIQuoteResponse() async {
        let service = DailyQuoteService(apiClient: StubDailyQuoteAPI(response: "not-json"))
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key"
        )

        do {
            _ = try await service.generate(for: "2026-09-01", configuration: configuration)
            XCTFail("Expected malformed response error")
        } catch let error as AIAPIError {
            guard case .invalidJSON = error else {
                XCTFail("Unexpected AI API error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct StubDailyQuoteAPI: AITextCompletionAPI {
    let response: String

    func complete(
        systemPrompt _: String,
        userPrompt _: String,
        configuration _: AIAPIConfiguration
    ) async throws -> String {
        response
    }
}
