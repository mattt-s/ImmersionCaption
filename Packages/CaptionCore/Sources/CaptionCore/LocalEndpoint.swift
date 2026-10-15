import Foundation

public enum EndpointError: Error, LocalizedError {
    case notLoopback
    public var errorDescription: String? {
        "Use a local Ollama address, such as http://127.0.0.1:11434. Remote servers are disabled."
    }
}

/// Restricts inference traffic to explicit loopback hosts. Redirects must also be disabled by the adapter.
public enum LocalEndpoint {
    public static func validate(_ address: String) throws -> URL {
        guard let parts = URLComponents(string: address),
              parts.scheme == "http",
              let host = parts.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let url = parts.url else { throw EndpointError.notLoopback }
        return url
    }
}
