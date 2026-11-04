import Foundation

/// One committed phrase of recognized speech. History is kept in memory.
public struct Caption: Identifiable, Equatable, Codable {
    public let id: UUID
    public let text: String
    public let createdAt: Date

    public init(text: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.createdAt = createdAt
    }
}

public enum SessionState: String {
    case stopped, starting, running, paused, failed

    public var canStart: Bool { self == .stopped || self == .paused || self == .failed }
}
