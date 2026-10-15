import XCTest
@testable import CaptionCore

final class TimedSegmentationTests: XCTestCase {
    func testPauseBetweenWordsDoesNotCutUnpunctuatedSpeech() {
        let text = "今天先这样我们明天再讨论"
        let timing = words(in: text, [("今天先这样", 0, 0.7), ("我们明天再讨论", 5, 1)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), [])
        XCTAssertEqual(segmenter.ingest(text, isFinal: true, segments: timing), [text])
    }

    func testLongDurationDoesNotCutContinuousSpeech() {
        let text = "今天我们想聊一聊学习英语的方法"
        let timing = words(in: text, [("今天我们", 0, 10), ("想聊一聊", 10, 10), ("学习英语的方法", 20, 10)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), [])
        XCTAssertEqual(segmenter.ingest(text + "。", isFinal: false, segments: timing), [text + "。"])
    }

    func testLongUnpunctuatedPartialWaitsForBoundary() {
        let text = String(repeating: "今天我们聊一聊学习英语的方法", count: 10)
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false), [])
        XCTAssertEqual(segmenter.ingest(text + "。", isFinal: false), [text + "。"])
    }

    func testAvailableCompleteSentenceTakesPriorityOverItsCommas() {
        var segmenter = TranscriptSegmenter()
        let text = "老板见有了巴结的机会，立刻答应帮忙。"
        XCTAssertEqual(segmenter.ingest(text, isFinal: false), [text])
    }

    func testPunctuationBeyondOldCharacterTargetsIsFound() {
        var segmenter = TranscriptSegmenter()
        let text = String(repeating: "今天我们聊一聊学习英语的方法", count: 6) + "，等大家准备好以后再一起出发。"
        XCTAssertEqual(segmenter.ingest(text, isFinal: false), [text])
    }

    func testPunctuationDelimitedClauseCanCommitBeforeSentenceIsAvailable() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("老板见有了巴结的机会，立刻答应", isFinal: false), ["老板见有了巴结的机会，"])
        XCTAssertEqual(segmenter.ingest("老板见有了巴结的机会，立刻答应帮忙。", isFinal: false), ["立刻答应帮忙。"])
    }

    func testFinalUnpunctuatedUtteranceKeepsItsCommasTogether() {
        var segmenter = TranscriptSegmenter()
        let text = "老板见有了巴结的机会，立刻答应帮忙"
        XCTAssertEqual(segmenter.ingest(text, isFinal: true), [text])
    }

    func testShortCommaPhraseWaits() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("谢谢，好的", isFinal: false), [])
        XCTAssertEqual(segmenter.ingest("谢谢，好的。", isFinal: false), ["谢谢，好的。"])
    }

    func testNumericSeparatorsAndAbbreviationsAreNotSentenceBoundaries() {
        var segmenter = TranscriptSegmenter()
        let text = "今天我们赚到了1,000元约定10:30讨论版本2.0和Dr. Lee的建议"
        XCTAssertEqual(segmenter.ingest(text, isFinal: false), [])
        XCTAssertEqual(segmenter.ingest(text + "。", isFinal: false), [text + "。"])
    }

    func testClosingQuoteStaysWithItsSentence() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("他说：“我们明天再讨论。”随后离开。", isFinal: false),
                       ["他说：“我们明天再讨论。”", "随后离开。"])
    }

    func testTimingAlignsAnEarlierRevisionWithoutSkippingNewSpeech() {
        var segmenter = TranscriptSegmenter()
        let original = "今天先这样。我们明天再讨论"
        let first = words(in: original, [("今天先这样。", 0, 0.7), ("我们明天再讨论", 1.1, 0.7)])
        XCTAssertEqual(segmenter.ingest(original, isFinal: false, segments: first), ["今天先这样。"])
        let revised = "今天就先这样。我们明天再讨论"
        let second = words(in: revised, [("今天就先这样。", 0, 0.7), ("我们明天再讨论", 1.1, 0.7)])
        XCTAssertEqual(segmenter.ingest(revised, isFinal: true, segments: second), ["我们明天再讨论"])
    }

    func testUTF16RangesPreserveEmojiAndProperNames() {
        let text = "🙂今天讨论ScreenCaptureKit的使用方式。"
        let timing = words(in: text, [("🙂今天", 0, 0.7), ("讨论ScreenCaptureKit的使用方式。", 5, 10)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), [text])
    }

    func testInvalidTimingAndOutOfBoundsRangesFallBackSafely() {
        let text = "今天先这样。我们明天再讨论"
        let invalid = [SpeechSegment(range: NSRange(location: Int.max, length: 1), startTime: 0, duration: 1),
                       SpeechSegment(range: NSRange(location: 0, length: 2), startTime: .nan, duration: 1),
                       SpeechSegment(range: NSRange(location: -1, length: 2), startTime: 0, duration: 1)]
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: invalid), ["今天先这样。"])
        XCTAssertEqual(segmenter.flush(), ["我们明天再讨论"])
    }

    private func words(in text: String, _ entries: [(String, TimeInterval, TimeInterval)]) -> [SpeechSegment] {
        let string = text as NSString
        var offset = 0
        return entries.map { value, start, duration in
            let range = string.range(of: value, options: [], range: NSRange(location: offset, length: string.length - offset))
            XCTAssertNotEqual(range.location, NSNotFound)
            offset = range.location + range.length
            return SpeechSegment(range: range, startTime: start, duration: duration)
        }
    }
}
