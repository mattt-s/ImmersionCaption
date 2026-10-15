import Foundation

/// Commits short speech clauses using punctuation, word timing, and size/duration targets.
/// Timed units and Foundation word boundaries preserve lexical units and align revisions.
/// The caller flushes stable drafts and resets when the recognition request changes.
public struct TranscriptSegmenter {
    private var committed = ""
    private var committedEndTime: TimeInterval?
    private var hypothesis = ""
    private var words: [(value: SpeechSegment, range: Range<String.Index>)] = []
    public let maximumCharacters: Int
    public let maximumDuration: TimeInterval
    public let pauseThreshold: TimeInterval
    private let minimumClauseCharacters: Int

    public init(maximumCharacters: Int = 28, maximumDuration: TimeInterval = 3.2,
                pauseThreshold: TimeInterval = 0.35, minimumClauseCharacters: Int = 10) {
        self.maximumCharacters = max(8, maximumCharacters)
        self.maximumDuration = max(0.5, maximumDuration)
        self.pauseThreshold = max(0.1, pauseThreshold)
        self.minimumClauseCharacters = max(2, min(minimumClauseCharacters, self.maximumCharacters))
    }

    public init(profile: CaptionLength) {
        self.init(maximumCharacters: profile.maximumCharacters,
                  maximumDuration: profile.maximumDuration,
                  pauseThreshold: profile.pauseThreshold)
    }

    /// Ranges refer to the untrimmed cumulative text. Invalid timing/ranges are ignored safely.
    public mutating func ingest(_ text: String, isFinal: Bool, segments: [SpeechSegment] = []) -> [String] {
        hypothesis = text
        words = segments.compactMap { segment in
            guard segment.startTime.isFinite, segment.duration.isFinite,
                  segment.startTime >= 0, segment.duration >= 0, segment.endTime.isFinite,
                  segment.range.location != NSNotFound, segment.range.length > 0,
                  segment.range.location >= 0,
                  segment.range.location <= text.utf16.count,
                  segment.range.length <= text.utf16.count - segment.range.location,
                  let range = Range(segment.range, in: text) else { return nil }
            return (value: segment, range: range)
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        return drain(flush: isFinal)
    }

    /// Commits the pending tail after a stable interval without inventing a sentence ending.
    public mutating func flush() -> [String] { drain(flush: true) }

    public mutating func reset() {
        committed = ""
        committedEndTime = nil
        hypothesis = ""
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
            if let time = words.filter({ $0.range.upperBound <= end }).map({ $0.value.endTime }).max() {
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
        if let time = committedEndTime, !words.isEmpty {
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
        // Providers without timestamps retain positional alignment as a conservative fallback.
        return hypothesis.index(hypothesis.startIndex, offsetBy: min(committed.count, hypothesis.count))
    }

    private func boundary(after start: String.Index, flush: Bool) -> String.Index? {
        let tail = hypothesis[start...]
        let limit = hypothesis.index(start, offsetBy: min(maximumCharacters, tail.count))
        let pendingWords = words.filter { $0.range.lowerBound >= start }
        var candidates: [String.Index] = []
        let strong: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "\n"]
        let soft: Set<Character> = ["，", ",", "：", ":"]
        var count = 0
        for index in tail.indices {
            count += 1
            guard count <= maximumCharacters else { break }
            let character = hypothesis[index]
            let next = hypothesis.index(after: index)
            let numericSeparator = (character == "," || character == ":") && index > start &&
                next < hypothesis.endIndex && hypothesis[hypothesis.index(before: index)].isNumber &&
                hypothesis[next].isNumber
            if strong.contains(character) ||
                (soft.contains(character) && !numericSeparator && count >= minimumClauseCharacters) {
                candidates.append(hypothesis.index(after: index))
            }
        }

        for (left, right) in zip(pendingWords, pendingWords.dropFirst()) {
            let end = right.range.lowerBound
            if right.value.startTime - left.value.endTime >= pauseThreshold - 0.000_001,
               end <= limit, hypothesis.distance(from: start, to: end) >= min(4, minimumClauseCharacters) {
                candidates.append(end)
            }
        }
        if let first = pendingWords.first {
            // Continuous fast speech may have no useful silence: bound its time span too.
            if let timedEnd = pendingWords.first(where: {
                $0.value.endTime - first.value.startTime >= maximumDuration - 0.000_001
            })?.range.upperBound, timedEnd <= limit {
                candidates.append(timedEnd)
            }
        }

        if tail.count >= maximumCharacters {
            if let wordEnd = pendingWords.map({ $0.range.upperBound }).filter({ $0 <= limit }).max() {
                candidates.append(wordEnd)
            } else if let first = pendingWords.first, first.range.lowerBound == start,
                      isUnbrokenLatinWord(hypothesis[first.range]) {
                // A long proper name may exceed the target; a multiword ASR unit may not.
                candidates.append(first.range.upperBound)
            } else {
                candidates.append(textBoundary(after: start, limit: limit))
            }
        }
        if flush { candidates.append(hypothesis.endIndex) }
        return candidates.filter { $0 > start }.min()
    }

    private func isUnbrokenLatinWord(_ value: Substring) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            $0.isASCII && CharacterSet.alphanumerics.contains($0)
        }
    }

    /// Apple recognition units can be whole clauses. Tokenize those locally instead of
    /// allowing one oversized unit to make an arbitrarily long subtitle.
    private func textBoundary(after start: String.Index, limit: String.Index) -> String.Index {
        var lastBoundary: String.Index?
        var firstWord: Range<String.Index>?
        hypothesis.enumerateSubstrings(in: start..<hypothesis.endIndex, options: [.byWords, .substringNotRequired]) {
            _, range, _, stop in
            if firstWord == nil { firstWord = range }
            if range.upperBound <= limit { lastBoundary = range.upperBound }
            else { stop = true }
        }
        if let lastBoundary = lastBoundary, lastBoundary > start { return lastBoundary }
        if let firstWord = firstWord, firstWord.lowerBound == start,
           isUnbrokenLatinWord(hypothesis[firstWord]) { return firstWord.upperBound }
        return limit
    }
}
