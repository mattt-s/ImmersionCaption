import XCTest
import CoreMedia
import CaptionCore
@testable import ImmersionCaption

@MainActor
final class CaptionSessionTests: XCTestCase {
    func testPauseDropsPendingAndRejectsLateTranslation() async throws {
        let capture = FakeCapture()
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: capture, speech: speech, translator: engine)
        await session.start()
        XCTAssertEqual(session.state, .running)
        speech.emit("第一句。第二句。")
        await waitUntil { engine.requests.count == 1 }
        await session.pause()
        engine.complete("Late result")
        await Task.yield()
        XCTAssertNil(session.currentCaption)
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(session.pendingPhrases, 0)
        XCTAssertEqual(session.state, .paused)
        XCTAssertGreaterThan(capture.stopCount, 0)
    }

    func testStopDuringSpeechPermissionCannotStartCaptureLater() async {
        let capture = FakeCapture()
        let speech = FakeSpeech()
        speech.holdStartup = true
        let session = CaptionSession(capture: capture, speech: speech, translator: HeldTranslator())
        let startup = Task { await session.start() }
        await waitUntil { speech.startup != nil }
        await session.stop()
        speech.startup?.resume()
        await startup.value
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(session.state, .stopped)
        XCTAssertFalse(session.isTransitioning)
    }

    func testOverloadDropsOldestPendingPhrase() async {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        speech.emit("一。")
        await waitUntil { engine.requests.count == 1 }
        speech.emit("一。二。三。四。五。")
        XCTAssertEqual(session.droppedPhrases, 1)
        engine.complete("One.")
        await waitUntil { engine.requests.count == 2 }
        XCTAssertEqual(engine.requests[1].source, "三。")
        XCTAssertEqual(engine.requests[1].context.first?.translation, "One.")
        await session.stop()
        engine.complete("Three.")
    }

    func testRestartRejectsOldRecognizerEvents() async {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        let oldCallback = speech.callback
        await session.pause()
        await session.start()
        oldCallback?(TranscriptEvent(utteranceID: UUID(), text: "过期。", isFinal: true))
        await Task.yield()
        XCTAssertTrue(engine.requests.isEmpty)
        await session.stop()
    }

    func testRecognitionFailureStopsBothAdapters() async {
        let speech = FakeSpeech()
        let capture = FakeCapture()
        let session = CaptionSession(capture: capture, speech: speech, translator: HeldTranslator())
        await session.start()
        speech.failure?(SpeechError.localModelUnavailable)
        await waitUntil { session.state == .failed && !session.isTransitioning }
        XCTAssertNotNil(session.errorMessage)
        XCTAssertNil(speech.callback)
        XCTAssertEqual(capture.stopCount, 1)
    }

    func testStopDuringCaptureStartupRejectsLateSuccess() async {
        let capture = FakeCapture()
        capture.holdStartup = true
        let speech = FakeSpeech()
        let session = CaptionSession(capture: capture, speech: speech, translator: HeldTranslator())
        let startup = Task { await session.start() }
        await waitUntil { capture.startup != nil }
        await session.stop()
        capture.startup?.resume()
        await startup.value
        XCTAssertEqual(session.state, .stopped)
        XCTAssertNil(speech.callback)
        XCTAssertNil(session.currentCaption)
    }

    func testFailureCompletingAfterExplicitStopDoesNotResurfaceError() async {
        let capture = FakeCapture()
        let speech = FakeSpeech()
        let session = CaptionSession(capture: capture, speech: speech, translator: HeldTranslator())
        await session.start()
        capture.holdNextStop = true
        speech.failure?(SpeechError.localModelUnavailable)
        await waitUntil { capture.pendingStop != nil }
        await session.stop()
        capture.pendingStop?.resume()
        await waitUntil { !session.isTransitioning }
        XCTAssertEqual(session.state, .stopped)
        XCTAssertNil(session.errorMessage)
    }

    func testStableUnpunctuatedPartialIsNotSentToTranslation() async throws {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        let partial = String(repeating: "今天我们聊一聊学习英语的方法", count: 5)
        speech.emit(partial)
        // Exceed the removed 650 ms timeout; text must still wait for punctuation.
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(engine.requests.isEmpty)
        speech.emit(partial + "。")
        await waitUntil { engine.requests.count == 1 }
        XCTAssertEqual(engine.requests.first?.source, partial + "。")
        await session.stop()
        engine.complete("A complete sentence.")
    }

    func testRequestRotationCarriesUnfinishedTextIntoNextRequest() async {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        speech.emit("今天我们决定")
        speech.utteranceID = UUID()
        speech.emit("等大家准备好以后再出发。")
        await waitUntil { engine.requests.count == 1 }
        XCTAssertEqual(engine.requests.first?.source, "今天我们决定等大家准备好以后再出发。")
        await session.stop()
        engine.complete("We'll leave once everyone is ready.")
    }

    func testPauseDiscardsUnfinishedCarry() async {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        speech.emit("这段没有说完的内容")
        await session.pause()
        await session.start()
        speech.emit("这是一段新的内容。")
        await waitUntil { engine.requests.count == 1 }
        XCTAssertEqual(engine.requests.first?.source, "这是一段新的内容。")
        await session.stop()
        engine.complete("New content.")
    }

    func testActualFinalResultTranslatesUnpunctuatedUtterance() async {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        speech.callback?(TranscriptEvent(utteranceID: speech.utteranceID, text: "谢谢你今天过来帮忙", isFinal: true))
        await waitUntil { engine.requests.count == 1 }
        XCTAssertEqual(engine.requests.first?.source, "谢谢你今天过来帮忙")
        await session.stop()
        engine.complete("Thanks for coming to help today.")
    }

    func testManualTranslationDoesNotTruncateInputAtFiveHundredCharacters() async {
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: FakeSpeech(), translator: engine)
        let source = String(repeating: "这是一段需要完整翻译的内容", count: 50) + "。"
        XCTAssertGreaterThan(source.count, 500)
        session.translateSample(source)
        await waitUntil { engine.requests.count == 1 }
        XCTAssertEqual(engine.requests.first?.source, source)
        await session.stop()
        engine.complete("A full translation.")
    }

    func testRevisedZeroTimedTranscriptDoesNotEnqueueOldClausesAgain() async {
        let speech = FakeSpeech()
        let engine = HeldTranslator()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, translator: engine)
        await session.start()
        let original = "他笑着说马上就去安排，大家发现他今天特别高兴，老板也看到了表现的机会，"
        func zeroTiming(_ text: String) -> [SpeechSegment] {
            [SpeechSegment(range: NSRange(location: 0, length: text.utf16.count), startTime: 0, duration: 0)]
        }
        speech.emit(original, segments: zeroTiming(original))
        await waitUntil { engine.requests.count == 1 }
        let pendingBefore = session.pendingPhrases
        let revised = "他笑着说马上就去安排，大家发现他今天特别高兴还一直哼着歌，老板也看到了表现的机会，"
        speech.emit(revised, segments: zeroTiming(revised))
        XCTAssertEqual(session.pendingPhrases, pendingBefore)
        XCTAssertEqual(session.droppedPhrases, 0)
        engine.complete("He said he'd arrange it right away.")
        await waitUntil { engine.requests.count == 2 }
        XCTAssertEqual(engine.requests[1].source, "大家发现他今天特别高兴，")
        await session.stop()
        engine.complete("They noticed he was in a good mood.")
    }

    private func waitUntil(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Timed out waiting for session work", file: file, line: line)
    }
}

@MainActor
private final class FakeCapture: SystemAudioCapturing {
    var startCount = 0
    var stopCount = 0
    var holdStartup = false
    var holdNextStop = false
    var startup: CheckedContinuation<Void, Never>?
    var pendingStop: CheckedContinuation<Void, Never>?
    func start(receive: @escaping (CMSampleBuffer) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws {
        startCount += 1
        if holdStartup { await withCheckedContinuation { startup = $0 } }
    }
    func stop() async {
        stopCount += 1
        if holdNextStop {
            holdNextStop = false
            await withCheckedContinuation { pendingStop = $0 }
        }
    }
}

@MainActor
private final class FakeSpeech: SpeechRecognizing {
    var callback: (@MainActor (TranscriptEvent) -> Void)?
    var failure: (@MainActor (Error) -> Void)?
    var holdStartup = false
    var startup: CheckedContinuation<Void, Never>?
    var utteranceID = UUID()
    var audioReceiver: (CMSampleBuffer) -> Void { { _ in } }
    func start(onTranscript: @escaping @MainActor (TranscriptEvent) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws {
        callback = onTranscript
        failure = onFailure
        if holdStartup { await withCheckedContinuation { startup = $0 } }
    }
    func stop() { callback = nil; failure = nil }
    func emit(_ text: String, segments: [SpeechSegment] = []) {
        callback?(TranscriptEvent(utteranceID: utteranceID, text: text, isFinal: false, segments: segments))
    }
}

@MainActor
private final class HeldTranslator: TranslationEngine {
    var requests: [TranslationInput] = []
    var pending: [CheckedContinuation<String, Error>] = []
    func translate(_ input: TranslationInput) async throws -> String {
        requests.append(input)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func complete(_ translation: String) { pending.removeFirst().resume(returning: translation) }
}
