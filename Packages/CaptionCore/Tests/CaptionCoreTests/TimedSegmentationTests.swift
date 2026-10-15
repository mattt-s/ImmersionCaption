import XCTest
@testable import CaptionCore

final class TimedSegmentationTests: XCTestCase {
    func testPauseBetweenWordsCommitsAShortClauseBeforeFinalization() {
        let text = "今天先这样我们明天再讨论"
        let timing = words(in: text, [("今天", 0, 0.3), ("先这样", 0.3, 0.4),
                                     ("我们", 1.1, 0.2), ("明天再讨论", 1.3, 0.5)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), ["今天先这样"])
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), [])
        XCTAssertEqual(segmenter.flush(), ["我们明天再讨论"])
    }

    func testTinyPausesDoNotSplitEveryWord() {
        let text = "今天我们一起去公园散步"
        let timing = words(in: text, [("今天", 0, 0.3), ("我们", 0.31, 0.3),
                                     ("一起去", 0.62, 0.3), ("公园散步", 0.93, 0.5)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), [])
        XCTAssertEqual(segmenter.flush(), [text])
    }

    func testPauseExactlyAtThresholdToleratesFloatingPointRounding() {
        let text = "今天先这样我们明天再讨论"
        let timing = words(in: text, [("今天先这样", 0.2, 0.4), ("我们明天再讨论", 0.95, 0.7)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), ["今天先这样"])
    }

    func testContinuousSpeechUsesDurationWhenThereIsNoPauseOrPunctuation() {
        let text = "今天我们想聊一聊学习英语的方法"
        let timing = words(in: text, [("今天", 0, 0.8), ("我们", 0.85, 0.8),
                                     ("想聊一聊", 1.7, 1.6), ("学习英语的方法", 3.35, 1)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), ["今天我们想聊一聊"])
        XCTAssertEqual(segmenter.flush(), ["学习英语的方法"])
    }

    func testLengthTargetPreservesARecognizedProperName() {
        let text = "今天讨论ScreenCaptureKit的使用方式"
        let timing = words(in: text, [("今天", 0, 0.2), ("讨论", 0.2, 0.2),
                                     ("ScreenCaptureKit", 0.4, 0.3), ("的使用方式", 0.7, 0.4)])
        var segmenter = TranscriptSegmenter(maximumCharacters: 8)
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), ["今天讨论", "ScreenCaptureKit"])
        XCTAssertEqual(segmenter.flush(), ["的使用方式"])
    }

    func testTimingAlignsAnEarlierRevisionWithoutSkippingNewSpeech() {
        var segmenter = TranscriptSegmenter()
        let original = "今天先这样我们明天再讨论"
        let first = words(in: original, [("今天先这样", 0, 0.7), ("我们明天再讨论", 1.1, 0.7)])
        XCTAssertEqual(segmenter.ingest(original, isFinal: false, segments: first), ["今天先这样"])
        let revised = "今天就先这样我们明天再讨论"
        let second = words(in: revised, [("今天就先这样", 0, 0.7), ("我们明天再讨论", 1.1, 0.7)])
        XCTAssertEqual(segmenter.ingest(revised, isFinal: true, segments: second), ["我们明天再讨论"])
    }

    func testUTF16RangesDoNotSplitEmojiOrOffsetChineseIncorrectly() {
        let text = "🙂今天先这样我们明天再讨论"
        let timing = words(in: text, [("🙂今天先这样", 0, 0.7), ("我们明天再讨论", 1.1, 0.7)])
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(text, isFinal: false, segments: timing), ["🙂今天先这样"])
        XCTAssertEqual(segmenter.flush(), ["我们明天再讨论"])
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

    func testLongCommaDelimitedClauseCommitsWithoutWaitingForASentenceEnd() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("这件事情我们明天再讨论，今天先休息", isFinal: false), ["这件事情我们明天再讨论，"])
        XCTAssertEqual(segmenter.flush(), ["今天先休息"])
    }

    func testShortCommaPhraseStaysTogether() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("谢谢，好的", isFinal: false), [])
        XCTAssertEqual(segmenter.flush(), ["谢谢，好的"])
    }

    func testNumericCommaIsNotASemanticBoundary() {
        var segmenter = TranscriptSegmenter()
        let text = "今天我们一共赚到了1,000元"
        XCTAssertEqual(segmenter.ingest(text, isFinal: false), [])
        XCTAssertEqual(segmenter.flush(), [text])
    }

    func testDefaultShortModeKeepsEveryCharacterAcrossMultipleCaptions() {
        let text = String(repeating: "今天我们聊一聊学习英语的方法", count: 6)
        var segmenter = TranscriptSegmenter(profile: .short)
        let phrases = segmenter.ingest(text, isFinal: true)
        XCTAssertTrue(phrases.allSatisfy { $0.count <= 28 })
        XCTAssertEqual(phrases.joined(), text)
    }

    func testAnOversizedMultiwordRecognitionUnitCannotBypassTheLengthTarget() {
        let text = String(repeating: "今天我们聊一聊学习英语的方法", count: 5)
        let timing = [SpeechSegment(range: NSRange(location: 0, length: text.utf16.count), startTime: 0, duration: 12)]
        var segmenter = TranscriptSegmenter()
        let phrases = segmenter.ingest(text, isFinal: true, segments: timing)
        XCTAssertGreaterThan(phrases.count, 1)
        XCTAssertTrue(phrases.allSatisfy { $0.count <= 28 })
        XCTAssertEqual(phrases.joined(), text)
    }

    func testUntimedFallbackDoesNotSplitALongLatinProperName() {
        let text = "ScreenCaptureKit今天的使用方式"
        var segmenter = TranscriptSegmenter(maximumCharacters: 8)
        let phrases = segmenter.ingest(text, isFinal: true)
        XCTAssertEqual(phrases.first, "ScreenCaptureKit")
        XCTAssertEqual(phrases.joined(), text)
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
