import Foundation
import CaptionCore

enum TranslationError: LocalizedError {
    case http(Int), missingModel, invalidResponse, truncated, empty, unavailable

    var errorDescription: String? {
        switch self {
        case .http(let code): return "The local translation server returned HTTP \(code). Check Ollama and the model setting."
        case .missingModel: return "The selected model is not installed in Ollama. Choose an installed model, such as translategemma:4b."
        case .invalidResponse: return "Ollama returned an incomplete or unexpected response."
        case .truncated: return "The translation exceeded its output limit. Try a shorter phrase."
        case .empty: return "The translation model returned no text."
        case .unavailable: return "Cannot reach local Ollama. Open Ollama or run ‘ollama serve’, then retry."
        }
    }
}

/// Loopback-only HTTP adapter. A replacement embedded engine only needs to implement TranslationEngine.
@MainActor
final class OllamaTranslationEngine: TranslationEngine {
    private let endpoint: () -> String
    private let model: () -> String
    private let session: URLSession

    init(endpoint: @escaping () -> String, model: @escaping () -> String, session: URLSession? = nil) {
        self.endpoint = endpoint
        self.model = model
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.connectionProxyDictionary = [:]
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 75
            self.session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }
    }

    func translate(_ input: TranslationInput) async throws -> String {
        let url = try LocalEndpoint.validate(endpoint()).appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: model().trimmingCharacters(in: .whitespacesAndNewlines),
            messages: [.init(role: "user", content: TranslationPrompt.make(for: input))]
        ))
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw TranslationError.unavailable
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
        if http.statusCode == 404 { throw TranslationError.missingModel }
        guard http.statusCode == 200 else { throw TranslationError.http(http.statusCode) }
        guard let result = try? JSONDecoder().decode(ChatResponse.self, from: data), result.done else {
            throw TranslationError.invalidResponse
        }
        guard result.doneReason != "length" else { throw TranslationError.truncated }
        let translation = result.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { throw TranslationError.empty }
        return translation
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream = false
    let keep_alive = "5m"
    let options = Options()

    struct Message: Encodable { let role: String; let content: String }
    struct Options: Encodable {
        let temperature = 0.0
        let num_ctx = 4096
        let num_predict = 384
    }
}

private struct ChatResponse: Decodable {
    let message: Message
    let done: Bool
    let doneReason: String?
    struct Message: Decodable { let content: String }
    enum CodingKeys: String, CodingKey {
        case message, done
        case doneReason = "done_reason"
    }
}

/// Prevents a local server from redirecting private dialogue to a remote endpoint.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
