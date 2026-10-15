import Foundation

/// One completed source phrase and its English translation. History is kept in memory.
public struct Caption: Identifiable, Equatable, Codable {
    public let id: UUID
    public let source: String
    public let translation: String
    public let createdAt: Date

    public init(source: String, translation: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.source = source
        self.translation = translation
        self.createdAt = createdAt
    }
}

public enum SessionState: String {
    case stopped, starting, running, paused, failed

    public var canStart: Bool { self == .stopped || self == .paused || self == .failed }
}
