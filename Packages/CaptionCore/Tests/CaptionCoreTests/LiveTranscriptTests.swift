import XCTest
@testable import CaptionCore

final class LiveTranscriptTests: XCTestCase {
    func testPartialAppearsWithoutPunctuationAndKeepsIdentityThroughRevisions() {
        var transcript = LiveTranscript()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1)
        XCTAssertTrue(transcript.update(requestID: id, text: "货传", languageIdentifier: "zh-CN", isFinal: false, at: date))
        XCTAssertTrue(transcript.update(requestID: id, text: "货船进港", languageIdentifier: "zh-CN", isFinal: false))
        XCTAssertEqual(transcript.captions.count, 1)
        XCTAssertEqual(transcript.captions.first?.text, "货船进港")
        XCTAssertEqual(transcript.captions.first?.id, id)
        XCTAssertEqual(transcript.captions.first?.createdAt, date)
    }

    func testDuplicatePartialAndFinalDoNotAppend() {
        var transcript = LiveTranscript()
        let id = UUID()
        transcript.update(requestID: id, text: "Hello", languageIdentifier: "en-US", isFinal: false)
        XCTAssertFalse(transcript.update(requestID: id, text: "Hello", languageIdentifier: "en-US", isFinal: false))
        XCTAssertTrue(transcript.update(requestID: id, text: "Hello", languageIdentifier: "en-US", isFinal: true))
        XCTAssertFalse(transcript.update(requestID: id, text: "Hello", languageIdentifier: "en-US", isFinal: true))
        XCTAssertEqual(transcript.captions.count, 1)
        XCTAssertEqual(transcript.captions.first?.isFinal, true)
    }

    func testEarlierWordsAndUnicodeCanBeReplacedOrShortened() {
        var transcript = LiveTranscript()
        let id = UUID()
        transcript.update(requestID: id, text: "🙂これは長い誤認識です", languageIdentifier: "ja-JP", isFinal: false)
        transcript.update(requestID: id, text: "🙂こんにちは", languageIdentifier: "ja-JP", isFinal: false)
        XCTAssertEqual(transcript.captions.map(\.text), ["🙂こんにちは"])
    }

    func testEmptyRevisionRetractsPartialAndBlankInitialDoesNothing() {
        var transcript = LiveTranscript()
        let id = UUID()
        XCTAssertFalse(transcript.update(requestID: id, text: " \n", languageIdentifier: "en-US", isFinal: false))
        transcript.update(requestID: id, text: "Mistake", languageIdentifier: "en-US", isFinal: false)
        XCTAssertTrue(transcript.update(requestID: id, text: "", languageIdentifier: "en-US", isFinal: false))
        XCTAssertTrue(transcript.captions.isEmpty)
    }

    func testFinalTextIsImmutable() {
        var transcript = LiveTranscript()
        let id = UUID()
        transcript.update(requestID: id, text: "Final", languageIdentifier: "en-US", isFinal: true)
        XCTAssertFalse(transcript.update(requestID: id, text: "Late", languageIdentifier: "en-US", isFinal: false))
        XCTAssertEqual(transcript.captions.first?.text, "Final")
    }

    func testRepeatedSpeechInDifferentRequestsIsPreservedAndBounded() {
        var transcript = LiveTranscript(capacity: 2)
        let first = UUID(), second = UUID(), third = UUID()
        for id in [first, second, third] {
            transcript.update(requestID: id, text: "Thanks", languageIdentifier: "en-US", isFinal: true)
        }
        XCTAssertEqual(transcript.captions.map(\.id), [second, third])
        XCTAssertEqual(transcript.captions.map(\.text), ["Thanks", "Thanks"])
        transcript.removeAll()
        XCTAssertTrue(transcript.captions.isEmpty)
    }
}
