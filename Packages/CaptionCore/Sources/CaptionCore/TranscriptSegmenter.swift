import Foundation

/// Converts cumulative recognizer hypotheses into bounded phrases.
/// A committed prefix cannot be revised. Before commitment, edits replace the pending draft.
/// The caller flushes after a quiet/stable interval and resets when the recognizer rotates.
public struct TranscriptSegmenter {
    private var committed = ""
    private var hypothesis = ""
    public let maximumCharacters: Int

    public init(maximumCharacters: Int = 80) {
        self.maximumCharacters = max(8, maximumCharacters)
    }

    /// Returns complete sentences or bounded clauses. Final hypotheses also flush their tail.
    public mutating func ingest(_ text: String, isFinal: Bool) -> [String] {
        hypothesis = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var phrases: [String] = []
        while let phrase = nextPhrase(flush: isFinal) {
            phrases.append(phrase)
        }
        return phrases
    }

    /// Commits the current draft even without punctuation (for stable partial recognition).
    public mutating func flush() -> [String] {
        var phrases: [String] = []
        while let phrase = nextPhrase(flush: true) { phrases.append(phrase) }
        return phrases
    }

    public mutating func reset() {
        committed = ""
        hypothesis = ""
    }

    private mutating func nextPhrase(flush: Bool) -> String? {
        // Recognizers can revise earlier characters. Align by character position after a
        // commitment instead of replaying the entire hypothesis and duplicating subtitles.
        let offset = min(committed.count, hypothesis.count)
        let tail = String(hypothesis.dropFirst(offset))
        guard !tail.isEmpty else { return nil }
        let characters = Array(tail)
        let delimiters: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "\n"]
        let boundary = characters.prefix(maximumCharacters).firstIndex(where: { delimiters.contains($0) })
        let count: Int
        if let boundary = boundary { count = boundary + 1 }
        else if characters.count >= maximumCharacters { count = maximumCharacters }
        else if flush { count = characters.count }
        else { return nil }
        let consumed = String(characters.prefix(count))
        committed = String(hypothesis.prefix(offset)) + consumed
        let phrase = consumed.trimmingCharacters(in: .whitespacesAndNewlines)
        // Skip punctuation-only drafts without starving the rest of the hypothesis.
        if phrase.isEmpty || phrase.allSatisfy({ delimiters.contains($0) }) {
            return nextPhrase(flush: flush)
        }
        return phrase
    }
}
