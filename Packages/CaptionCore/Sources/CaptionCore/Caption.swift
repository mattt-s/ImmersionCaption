import Foundation

/// The latest text for one recognition request; partial updates preserve its identity.
public struct Caption: Identifiable, Equatable, Codable {
    public let id: UUID
    public let text: String
    public let languageIdentifier: String
    public let isFinal: Bool
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, languageIdentifier: String = "",
                isFinal: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.languageIdentifier = languageIdentifier
        self.isFinal = isFinal
        self.createdAt = createdAt
    }
}

public enum SessionState: String {
    case stopped, starting, running, paused, failed
    public var canStart: Bool { self == .stopped || self == .paused || self == .failed }
}
