import XCTest
@testable import CaptionCore

final class FinalTranscriptGateTests: XCTestCase {
    func testPunctuatedDraftsAndTheirRevisionsArePreviewOnly() {
        var gate = FinalTranscriptGate()
        let id = UUID()
        XCTAssertNil(gate.consume(utteranceID: id, text: "货船进入黄埔港，", isFinal: false))
        XCTAssertNil(gate.consume(utteranceID: id, text: "货船进入黄埔岗，另一部分往北走。", isFinal: false))
        let final = "货船进入黄埔港，另一部分继续往北走。"
        XCTAssertEqual(gate.consume(utteranceID: id, text: final, isFinal: true), final)
    }

    func testEntireFinalResultIsPassedWithoutSplittingOrTruncating() {
        var gate = FinalTranscriptGate()
        let final = String(repeating: "🙂这是需要完整翻译的内容，不能在中间切断。", count: 40)
        XCTAssertEqual(gate.consume(utteranceID: UUID(), text: final, isFinal: true), final)
    }

    func testDuplicateFinalWithDifferentTextIsIgnored() {
        var gate = FinalTranscriptGate()
        let id = UUID()
        XCTAssertEqual(gate.consume(utteranceID: id, text: "黄埔港。", isFinal: true), "黄埔港。")
        XCTAssertNil(gate.consume(utteranceID: id, text: "黄埔岗。", isFinal: true))
    }

    func testLateDuplicateIsIgnoredAfterAnotherRequestCompletes() {
        var gate = FinalTranscriptGate()
        let earlier = UUID()
        _ = gate.consume(utteranceID: earlier, text: "第一段。", isFinal: true)
        _ = gate.consume(utteranceID: UUID(), text: "第二段。", isFinal: true)
        XCTAssertNil(gate.consume(utteranceID: earlier, text: "第一段。", isFinal: true))
    }

    func testGenuineRepeatedSpeechInDifferentRequestsIsPreserved() {
        var gate = FinalTranscriptGate()
        XCTAssertEqual(gate.consume(utteranceID: UUID(), text: "谢谢。", isFinal: true), "谢谢。")
        XCTAssertEqual(gate.consume(utteranceID: UUID(), text: "谢谢。", isFinal: true), "谢谢。")
    }

    func testEmptyFinalStillCompletesItsRequest() {
        var gate = FinalTranscriptGate()
        let id = UUID()
        XCTAssertNil(gate.consume(utteranceID: id, text: " \n ", isFinal: true))
        XCTAssertNil(gate.consume(utteranceID: id, text: "后来出现的内容", isFinal: true))
    }

    func testResetClearsSessionScopedTracking() {
        var gate = FinalTranscriptGate()
        let id = UUID()
        _ = gate.consume(utteranceID: id, text: "谢谢。", isFinal: true)
        gate.reset()
        XCTAssertEqual(gate.consume(utteranceID: id, text: "谢谢。", isFinal: true), "谢谢。")
    }

    func testDuplicateTrackingHasBoundedCapacity() {
        var gate = FinalTranscriptGate(capacity: 2)
        let first = UUID()
        _ = gate.consume(utteranceID: first, text: "一", isFinal: true)
        _ = gate.consume(utteranceID: UUID(), text: "二", isFinal: true)
        _ = gate.consume(utteranceID: UUID(), text: "三", isFinal: true)
        XCTAssertEqual(gate.consume(utteranceID: first, text: "一", isFinal: true), "一")
    }
}
