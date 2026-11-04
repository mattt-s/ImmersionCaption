import Foundation

/// Bounded, revisable transcript snapshots. A request contributes one history entry,
/// replaced in place as its hypothesis changes; punctuation never gates display.
public struct LiveTranscript {
    public private(set) var captions: [Caption] = []
    private let capacity: Int

    public init(capacity: Int = 300) { self.capacity = max(1, capacity) }

    /// Returns whether visible/history content changed. Empty revisions retract an entry;
    /// a finalized entry is immutable. Request ordering is enforced by the speech adapter.
    @discardableResult
    public mutating func update(requestID: UUID, text: String, languageIdentifier: String,
                                isFinal: Bool, at date: Date = Date()) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = captions.firstIndex(where: { $0.id == requestID }) {
            let previous = captions[index]
            guard !previous.isFinal else { return false }
            if text.isEmpty {
                captions.remove(at: index)
                return true
            }
            guard previous.text != text || previous.isFinal != isFinal else { return false }
            captions[index] = Caption(id: requestID, text: text,
                                      languageIdentifier: previous.languageIdentifier,
                                      isFinal: isFinal, createdAt: previous.createdAt)
        } else {
            guard !text.isEmpty else { return false }
            captions.append(Caption(id: requestID, text: text, languageIdentifier: languageIdentifier,
                                    isFinal: isFinal, createdAt: date))
            if captions.count > capacity { captions.removeFirst(captions.count - capacity) }
        }
        return true
    }

    public mutating func removeAll() { captions.removeAll() }
}
