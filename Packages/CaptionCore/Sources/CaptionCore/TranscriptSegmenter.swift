import Foundation

/// Commits complete punctuated sentences, or punctuation-delimited clauses while a
/// sentence is still being recognized. Timing is used only to align revisions, never to cut text.
public struct TranscriptSegmenter {
    private var committed = ""
    private var committedEndTime: TimeInterval?
    private var alignedConsumedCharacters = 0
    private var hypothesis = ""
    private var words: [(value: SpeechSegment, range: Range<String.Index>)] = []
    private var continuation = ""
    private let minimumClauseCharacters = 10

    public init() {}

    /// Carries an unfinished phrase across a recognition-request rotation. Native request
    /// boundaries are not linguistic boundaries; timing and revision offsets restart here.
    public mutating func beginUtterance() {
        let pending = hypothesis.isEmpty ? continuation : String(hypothesis[pendingStart()...])
        reset()
        continuation = pending
    }

    /// Ranges refer to the untrimmed cumulative text. Invalid timing/ranges are ignored safely.
    public mutating func ingest(_ text: String, isFinal: Bool, segments: [SpeechSegment] = []) -> [String] {
        let combined = continuation + text
        alignedConsumedCharacters = TranscriptCursor.align(alignedConsumedCharacters, from: hypothesis, to: combined)
        hypothesis = combined
        words = segments.compactMap { segment in
            guard segment.startTime.isFinite, segment.duration.isFinite,
                  segment.startTime >= 0, segment.duration >= 0, segment.endTime.isFinite,
                  segment.range.location != NSNotFound, segment.range.length > 0,
                  segment.range.location >= 0,
                  segment.range.location <= text.utf16.count,
                  segment.range.length <= text.utf16.count - segment.range.location,
                  let range = Range(NSRange(location: segment.range.location + continuation.utf16.count,
                                             length: segment.range.length), in: combined) else { return nil }
            return (value: segment, range: range)
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        return drain(flush: isFinal)
    }

    /// Completes an actual final recognition result. Never call this for a timer, pause,
    /// or request rotation: those events do not establish a complete utterance.
    public mutating func flush() -> [String] { drain(flush: true) }

    public mutating func reset() {
        committed = ""
        committedEndTime = nil
        alignedConsumedCharacters = 0
        hypothesis = ""
        continuation = ""
        words.removeAll()
    }

    private mutating func drain(flush: Bool) -> [String] {
        var phrases: [String] = []
        while true {
            let start = pendingStart()
            guard start < hypothesis.endIndex,
                  let end = boundary(after: start, flush: flush), end > start else { break }
            let phrase = String(hypothesis[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            committed = String(hypothesis[..<end])
            alignedConsumedCharacters = committed.count
            if let time = words.filter({ $0.range.upperBound <= end && $0.value.endTime > 0 })
                .map({ $0.value.endTime }).max() {
                committedEndTime = max(committedEndTime ?? 0, time)
            }
            let hasContent = phrase.unicodeScalars.contains {
                !CharacterSet.punctuationCharacters.contains($0) &&
                !CharacterSet.whitespacesAndNewlines.contains($0)
            }
            if hasContent { phrases.append(phrase) }
        }
        return phrases
    }

    private func pendingStart() -> String.Index {
        if hypothesis.hasPrefix(committed) {
            return hypothesis.index(hypothesis.startIndex, offsetBy: committed.count)
        }
        // An earlier word can change length after commitment. Timing anchors avoid replaying
        // old speech or losing a new word merely because UTF-16 positions shifted.
        if let time = committedEndTime, words.contains(where: { $0.value.endTime > 0 }) {
            let oldWords = words.filter { $0.value.startTime < time - 0.01 }
            var start = oldWords.map { $0.range.upperBound }.max() ?? hypothesis.startIndex
            while start < hypothesis.endIndex,
                  hypothesis[start].unicodeScalars.allSatisfy({
                      CharacterSet.punctuationCharacters.contains($0) ||
                      CharacterSet.whitespacesAndNewlines.contains($0)
                  }) {
                start = hypothesis.index(after: start)
            }
            return start
        }
        // All-zero timings contain no audio-position information. Follow unchanged text
        // anchors across revisions instead of treating zero as a consumed audio watermark.
        return hypothesis.index(hypothesis.startIndex, offsetBy: min(alignedConsumedCharacters, hypothesis.count))
    }

    private func boundary(after start: String.Index, flush: Bool) -> String.Index? {
        var clauseEnd: String.Index?
        let sentencePunctuation: Set<Character> = ["。", "！", "？", "!", "?", "\n"]
        let clausePunctuation: Set<Character> = ["，", ",", "：", ":", "；", ";"]
        var count = 0
        for index in hypothesis[start...].indices {
            count += 1
            let character = hypothesis[index]
            let next = hypothesis.index(after: index)
            if sentencePunctuation.contains(character) || isSentencePeriod(at: index) {
                // Prefer the first complete sentence, even if a comma occurs earlier or
                // the sentence is longer than a subtitle panel can display at once.
                return includingClosingQuotes(after: next)
            }
            let numericSeparator = (character == "," || character == ":") && index > start &&
                next < hypothesis.endIndex && hypothesis[hypothesis.index(before: index)].isNumber &&
                hypothesis[next].isNumber
            if clauseEnd == nil, clausePunctuation.contains(character), !numericSeparator,
               count >= minimumClauseCharacters {
                clauseEnd = includingClosingQuotes(after: next)
            }
        }
        // An actual final result can contain a complete unpunctuated utterance. Keep it
        // intact rather than subdividing its commas. Partial text otherwise waits.
        if flush { return hypothesis.endIndex }
        return clauseEnd
    }

    private func includingClosingQuotes(after end: String.Index) -> String.Index {
        let closers: Set<Character> = ["”", "’", "」", "』", "）", ")", "]", "}", "\"", "'"]
        var end = end
        while end < hypothesis.endIndex, closers.contains(hypothesis[end]) {
            end = hypothesis.index(after: end)
        }
        return end
    }

    /// Avoids interpreting decimal points, URLs, and common English abbreviations as stops.
    private func isSentencePeriod(at index: String.Index) -> Bool {
        guard hypothesis[index] == "." else { return false }
        let next = hypothesis.index(after: index)
        guard next == hypothesis.endIndex || hypothesis[next].isWhitespace ||
              includingClosingQuotes(after: next) > next else { return false }
        var tokenStart = index
        while tokenStart > hypothesis.startIndex {
            let previous = hypothesis.index(before: tokenStart)
            let character = hypothesis[previous]
            guard character == "." || character.unicodeScalars.allSatisfy({
                $0.isASCII && CharacterSet.letters.contains($0)
            }) else { break }
            tokenStart = previous
        }
        let token = String(hypothesis[tokenStart..<next]).lowercased()
        let abbreviations: Set<String> = ["mr.", "mrs.", "ms.", "dr.", "prof.", "vs.", "etc.", "e.g.", "i.e."]
        if abbreviations.contains(token) { return false }
        let initials = token.split(separator: ".")
        return !(initials.count > 1 && initials.allSatisfy { $0.count == 1 })
    }
}
