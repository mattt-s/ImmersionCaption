import Foundation

/// Aligns a consumed character boundary across cumulative ASR text revisions when audio
/// timestamps are unavailable. Insertions inside consumed text are revisions, not new speech.
enum TranscriptCursor {
    static func align(_ consumed: Int, from previous: String, to current: String) -> Int {
        let old = Array(previous)
        let new = Array(current)
        let consumed = min(consumed, old.count)
        guard consumed > 0 else { return 0 }
        if new.starts(with: old.prefix(consumed)) { return consumed }

        let changes = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        let oldAnchors = old.indices.filter { !removed.contains($0) }
        let newAnchors = new.indices.filter { !inserted.contains($0) }
        var end: Int?
        var lastOldAnchor: Int?
        for (oldIndex, newIndex) in zip(oldAnchors, newAnchors) {
            guard oldIndex < consumed else { break }
            // Repeated punctuation can match the end of newly appended speech in an
            // otherwise minimal diff. Use content as the anchor, then its local separator.
            guard !isSeparator(old[oldIndex]) else { continue }
            end = newIndex + 1
            lastOldAnchor = oldIndex
        }
        if var end = end, let lastOldAnchor = lastOldAnchor {
            var remainingSeparators = consumed - lastOldAnchor - 1
            while end < new.count, remainingSeparators > 0, isSeparator(new[end]) {
                end += 1
                remainingSeparators -= 1
            }
            return end
        }
        // A completely rewritten transcript has no reliable text anchor. Retain positional
        // consumption rather than resetting to zero and replaying an entire passage.
        return end ?? min(consumed, new.count)
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }
}
