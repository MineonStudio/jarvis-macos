@testable import Jarvis
import XCTest

final class AIConnectionRequestTests: XCTestCase {
    // 回归：json_object 模式下 prompt 必须含 "json" 字样，否则 DeepSeek/OpenAI 返回 400
    func testConnectionTestRequestPromptMentionsJSONForJSONObjectMode() async throws {
        final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
            nonisolated(unsafe) static var capturedBody: Data?

            override class func canInit(with request: URLRequest) -> Bool { true }
            override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

            override func startLoading() {
                // URLSession 转发时会把 httpBody 转成 httpBodyStream，两者都要兜底
                if let body = request.httpBody {
                    Self.capturedBody = body
                } else if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var data = Data()
                    let bufferSize = 4096
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                    defer { buffer.deallocate() }
                    while stream.hasBytesAvailable {
                        let count = stream.read(buffer, maxLength: bufferSize)
                        if count <= 0 { break }
                        data.append(buffer, count: count)
                    }
                    Self.capturedBody = data
                }
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                let envelope = #"{"choices":[{"message":{"role":"assistant","content":"{\"ok\":true}"}}]}"#
                client?.urlProtocol(self, didLoad: Data(envelope.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }

            override func stopLoading() {}
        }

        URLProtocol.registerClass(RecordingURLProtocol.self)
        defer { URLProtocol.unregisterClass(RecordingURLProtocol.self) }

        let client = OpenAICompatibleAPIClient()
        let configuration = AIAPIConfiguration(
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model",
            apiKey: "test-key"
        )
        try await client.testConnection(configuration: configuration)

        let body = try XCTUnwrap(RecordingURLProtocol.capturedBody)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(
            text.lowercased().contains("json"),
            "json_object 模式的请求 prompt 必须包含 'json'，否则服务端会以 400 拒绝"
        )
    }
}
