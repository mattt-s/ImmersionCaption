import XCTest
import CaptionCore
@testable import ImmersionCaption

@MainActor
final class OllamaTranslationEngineTests: XCTestCase {
    func testRequestMatchesLocalTranslateGemmaContract() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/api/chat")
            XCTAssertEqual(request.httpMethod, "POST")
            // URLSession may expose the encoded body as a stream in URLProtocol.
            let data = request.httpBody ?? Self.read(request.httpBodyStream)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["model"] as? String, "translategemma:4b")
            XCTAssertEqual(body["stream"] as? Bool, false)
            let options = try XCTUnwrap(body["options"] as? [String: Any])
            XCTAssertEqual(options["temperature"] as? Double, 0)
            let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
            XCTAssertEqual(messages.count, 1)
            XCTAssertEqual(messages.first?["role"], "user")
            XCTAssertTrue(messages.first?["content"]?.contains("别着急") == true)
            XCTAssertTrue(messages.first?["content"]?.contains("with no alternative versions") == true)
            return (200, #"{"done":true,"message":{"content":"Take your time."}}"#)
        }
        let result = try await makeEngine().translate(TranslationInput(source: "别着急"))
        XCTAssertEqual(result, "Take your time.")
    }

    func testRejectsMissingModelIncompleteEmptyAndTruncatedResults() async {
        let cases = [
            (404, #"{"error":"model not found"}"#),
            (200, #"{"done":false,"message":{"content":"partial"}}"#),
            (200, #"{"done":true,"message":{"content":"  "}}"#),
            (200, #"{"done":true,"done_reason":"length","message":{"content":"cut off"}}"#),
            (200, "not JSON"),
            (302, "")
        ]
        for (code, body) in cases {
            StubURLProtocol.handler = { _ in (code, body) }
            do {
                _ = try await makeEngine().translate(TranslationInput(source: "你好"))
                XCTFail("Expected response rejection for \(code): \(body)")
            } catch { XCTAssertTrue(error is TranslationError) }
        }
    }

    func testRejectsRemoteEndpointBeforeNetworkRequest() async {
        let engine = OllamaTranslationEngine(endpoint: { "http://example.com" }, model: { "translategemma:4b" })
        do { _ = try await engine.translate(TranslationInput(source: "你好")); XCTFail("Remote address accepted") }
        catch { XCTAssertTrue(error is EndpointError) }
    }

    private func makeEngine() -> OllamaTranslationEngine {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return OllamaTranslationEngine(endpoint: { "http://127.0.0.1:11434" }, model: { "translategemma:4b" }, session: URLSession(configuration: config))
    }

    nonisolated private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
