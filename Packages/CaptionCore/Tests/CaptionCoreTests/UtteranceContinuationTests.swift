import XCTest
@testable import CaptionCore

final class UtteranceContinuationTests: XCTestCase {
    func testRotationCarriesOnlyUncommittedTail() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("第一句话。接下来我们决定", isFinal: false), ["第一句话。"])
        segmenter.beginUtterance()
        XCTAssertEqual(segmenter.ingest("先准备好再出发。", isFinal: false), ["接下来我们决定先准备好再出发。"])
    }

    func testMultipleRotationsWithoutPunctuationDoNotForceCuts() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("大家决定", isFinal: false), [])
        segmenter.beginUtterance()
        XCTAssertEqual(segmenter.ingest("等准备好以后", isFinal: false), [])
        segmenter.beginUtterance()
        // A restart with no callbacks must not lose the carried tail.
        segmenter.beginUtterance()
        XCTAssertEqual(segmenter.ingest("再一起出发。", isFinal: false), ["大家决定等准备好以后再一起出发。"])
    }

    func testRotatedRequestRevisionsKeepEmojiOffsetAndRejectReplays() {
        var segmenter = TranscriptSegmenter()
        _ = segmenter.ingest("🙂大家决定", isFinal: false)
        segmenter.beginUtterance()
        let partial = "等准备好以后再出发。随后休息"
        let length = ("等准备好以后再出发。" as NSString).length
        let units = [SpeechSegment(range: NSRange(location: 0, length: length), startTime: 0, duration: 2),
                     SpeechSegment(range: NSRange(location: length, length: 4), startTime: 3, duration: 1)]
        XCTAssertEqual(segmenter.ingest(partial, isFinal: false, segments: units), ["🙂大家决定等准备好以后再出发。"])
        XCTAssertEqual(segmenter.ingest(partial, isFinal: false, segments: units), [])
        let revised = "等全部准备好以后再出发。随后休息。"
        let revisedLength = ("等全部准备好以后再出发。" as NSString).length
        let revisedUnits = [SpeechSegment(range: NSRange(location: 0, length: revisedLength), startTime: 0, duration: 2),
                            SpeechSegment(range: NSRange(location: revisedLength, length: 5), startTime: 3, duration: 1)]
        XCTAssertEqual(segmenter.ingest(revised, isFinal: true, segments: revisedUnits), ["随后休息。"])
    }

    func testFinalUtteranceDoesNotCarryAlreadyCommittedText() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("谢谢你的帮助", isFinal: true), ["谢谢你的帮助"])
        segmenter.beginUtterance()
        XCTAssertEqual(segmenter.ingest("我们明天见。", isFinal: false), ["我们明天见。"])
    }
}
