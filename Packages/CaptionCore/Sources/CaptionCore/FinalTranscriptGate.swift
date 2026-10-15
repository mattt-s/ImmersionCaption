import Foundation

/// Accepts each finalized recognition request once. Partial text is preview-only and
/// never contributes characters to translation input, even when it contains punctuation.
public struct FinalTranscriptGate {
    private var completed = Set<UUID>()
    private var completionOrder: [UUID] = []
    private let capacity: Int

    /// Bounds duplicate tracking; adapters must also reject callbacks from retired requests.
    public init(capacity: Int = 128) { self.capacity = max(1, capacity) }

    /// Returns the entire finalized text, or nil for a draft, empty result, or duplicate.
    public mutating func consume(utteranceID: UUID, text: String, isFinal: Bool) -> String? {
        guard isFinal, completed.insert(utteranceID).inserted else { return nil }
        completionOrder.append(utteranceID)
        if completionOrder.count > capacity { completed.remove(completionOrder.removeFirst()) }
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? nil : source
    }

    /// Clears session-scoped duplicate tracking on start, pause, stop, or failure.
    public mutating func reset() {
        completed.removeAll()
        completionOrder.removeAll()
    }
}
