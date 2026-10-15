import XCTest
@testable import CaptionCore

final class TranscriptSegmenterTests: XCTestCase {
    func testEmitsSentencesOnceAndFinalTail() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("别着急。慢慢来", isFinal: false), ["别着急。"])
        XCTAssertEqual(segmenter.ingest("别着急。慢慢来", isFinal: false), [])
        XCTAssertEqual(segmenter.ingest("别着急。慢慢来", isFinal: true), ["慢慢来"])
        XCTAssertEqual(segmenter.flush(), [])
    }

    func testRevisionsBeforeCommitReplaceDraft() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("我们明天去北京", isFinal: false), [])
        XCTAssertEqual(segmenter.ingest("我们明天去南京", isFinal: false), [])
        XCTAssertEqual(segmenter.flush(), ["我们明天去南京"])
    }

    func testFinalizedTailDoesNotReplayOnNextUpdate() {
        var segmenter = TranscriptSegmenter()
        _ = segmenter.ingest("今天很开心", isFinal: false)
        XCTAssertEqual(segmenter.flush(), ["今天很开心"])
        XCTAssertEqual(segmenter.ingest("今天很开心因为见到了你。", isFinal: true), ["因为见到了你。"])
    }

    func testKeepsLongPhrasesIntact() {
        var segmenter = TranscriptSegmenter()
        let text = String(repeating: "好", count: 18)
        XCTAssertEqual(segmenter.ingest(text, isFinal: true).map { $0.count }, [18])
    }

    func testPunctuationAndWhitespaceDoNotBecomeCaptions() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest(" ？！\n你好！  ", isFinal: true), ["你好！"])
    }

    func testResetAllowsSamePhraseInNewUtterance() {
        var segmenter = TranscriptSegmenter()
        XCTAssertEqual(segmenter.ingest("谢谢", isFinal: true), ["谢谢"])
        segmenter.reset()
        XCTAssertEqual(segmenter.ingest("谢谢", isFinal: true), ["谢谢"])
    }

    func testShorterRevisionDoesNotCrashOrReplay() {
        var segmenter = TranscriptSegmenter()
        _ = segmenter.ingest("我们明天见", isFinal: true)
        XCTAssertEqual(segmenter.ingest("我们明天", isFinal: true), [])
    }
}
