import XCTest
@testable import CaptionCore

final class TranscriptReplayTests: XCTestCase {
    func testZeroTimestampRevisionDoesNotReplayCommittedClauses() {
        var segmenter = TranscriptSegmenter(maximumCharacters: 200)
        let original = "他笑着说马上就去安排，大家发现他今天特别高兴，老板也看到了表现的机会，"
        XCTAssertEqual(segmenter.ingest(original, isFinal: false, segments: zeroTiming(original)).count, 3)
        let revised = "他笑着说马上就去安排，大家发现他今天特别高兴还一直哼着歌，老板也看到了表现的机会，"
        XCTAssertEqual(segmenter.ingest(revised, isFinal: false, segments: zeroTiming(revised)), [])
        XCTAssertEqual(segmenter.flush(), [])
    }

    func testRevisionAndNewSpeechCommitOnlyNewTailWithoutTimings() {
        var segmenter = TranscriptSegmenter(maximumCharacters: 200)
        let original = "他笑着说马上就去安排，大家发现他今天特别高兴，老板也看到了表现的机会，"
        _ = segmenter.ingest(original, isFinal: true)
        let revised = "他笑着说马上就去安排，大家发现他今天特别高兴还一直哼着歌，老板也看到了表现的机会，随后大家一起出门了。"
        XCTAssertEqual(segmenter.ingest(revised, isFinal: true), ["随后大家一起出门了。"])
    }

    func testZeroTimingsAfterPreviouslyValidTimingsUseTextAnchors() {
        var segmenter = TranscriptSegmenter(maximumCharacters: 200)
        let original = "今天先这样。我们明天再讨论。"
        let timing = [SpeechSegment(range: NSRange(location: 0, length: 6), startTime: 0, duration: 1),
                      SpeechSegment(range: NSRange(location: 6, length: 8), startTime: 1.2, duration: 1)]
        _ = segmenter.ingest(original, isFinal: true, segments: timing)
        let revised = "今天就先这样。我们明天再讨论。下午再联系。"
        XCTAssertEqual(segmenter.ingest(revised, isFinal: true, segments: zeroTiming(revised)), ["下午再联系。"])
    }

    func testRepeatedSpokenWordsAreNotGloballyDeduplicated() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("谢谢。", isFinal: true), ["谢谢。"])
        XCTAssertEqual(segmenter.ingest("谢谢。谢谢。", isFinal: true), ["谢谢。"])
        segmenter.reset()
        XCTAssertEqual(segmenter.ingest("谢谢。", isFinal: true), ["谢谢。"])
    }

    func testCursorHandlesUTF16TextAndEarlierDeletion() {
        let previous = "🙂今天就先这样。明天再讨论。"
        let current = "🙂今天先这样。明天再讨论。新增内容。"
        let offset = TranscriptCursor.align(previous.count, from: previous, to: current)
        XCTAssertEqual(String(current.dropFirst(offset)), "新增内容。")
    }

    private func zeroTiming(_ text: String) -> [SpeechSegment] {
        [SpeechSegment(range: NSRange(location: 0, length: text.utf16.count), startTime: 0, duration: 0)]
    }
}
