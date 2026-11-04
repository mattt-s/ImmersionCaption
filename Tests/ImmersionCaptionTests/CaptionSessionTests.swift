import XCTest
import CoreMedia
import CaptionCore
@testable import ImmersionCaption

@MainActor
final class CaptionSessionTests: XCTestCase {
    func testPunctuatedPartialPublishesRecognizedTextImmediately() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.emit("老板见有了巴结的机会，立刻答应帮忙。")
        XCTAssertEqual(session.currentCaption?.text, "老板见有了巴结的机会，立刻答应帮忙。")
        XCTAssertEqual(session.history.map(\.text), ["老板见有了巴结的机会，立刻答应帮忙。"])
        XCTAssertEqual(session.sourceDraft, "老板见有了巴结的机会，立刻答应帮忙。")
        await session.stop()
    }

    func testAllPhrasesInOneEventEnterHistoryWithoutQueueDrops() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.emit("一。二。三。四。五。六。")
        XCTAssertEqual(session.history.map(\.text), ["一。", "二。", "三。", "四。", "五。", "六。"])
        XCTAssertEqual(session.currentCaption?.text, "六。")
        await session.stop()
    }

    func testPauseHidesCaptionAndRejectsLateRecognition() async {
        let capture = FakeCapture()
        let speech = FakeSpeech()
        let session = CaptionSession(capture: capture, speech: speech)
        await session.start()
        speech.emit("第一句。")
        let oldCallback = speech.callback
        await session.pause()
        oldCallback?(TranscriptEvent(utteranceID: speech.utteranceID, text: "过期结果。", isFinal: true))
        XCTAssertNil(session.currentCaption)
        XCTAssertEqual(session.sourceDraft, "")
        XCTAssertEqual(session.history.map(\.text), ["第一句。"])
        XCTAssertEqual(session.state, .paused)
        XCTAssertGreaterThan(capture.stopCount, 0)
    }

    func testStopDuringSpeechPermissionCannotStartCaptureLater() async {
        let capture = FakeCapture()
        let speech = FakeSpeech()
        speech.holdStartup = true
        let session = CaptionSession(capture: capture, speech: speech)
        let startup = Task { await session.start() }
        await waitUntil { speech.startup != nil }
        await session.stop()
        speech.startup?.resume()
        await startup.value
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(session.state, .stopped)
        XCTAssertFalse(session.isTransitioning)
    }

    func testRestartRejectsOldRecognizerEvents() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        let oldCallback = speech.callback
        await session.pause()
        await session.start()
        oldCallback?(TranscriptEvent(utteranceID: UUID(), text: "过期。", isFinal: true))
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertNil(session.currentCaption)
        speech.emit("新的字幕。")
        XCTAssertEqual(session.currentCaption?.text, "新的字幕。")
        await session.stop()
    }

    func testRecognitionFailureStopsBothAdapters() async {
        let speech = FakeSpeech()
        let capture = FakeCapture()
        let session = CaptionSession(capture: capture, speech: speech)
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
        let session = CaptionSession(capture: capture, speech: speech)
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
        let session = CaptionSession(capture: capture, speech: speech)
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

    func testUnpunctuatedPartialStillWaitsForBoundary() async throws {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        let partial = String(repeating: "今天我们聊一聊学习英语的方法", count: 5)
        speech.emit(partial)
        // Protect the existing punctuation policy against reintroducing a draft timer.
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertNil(session.currentCaption)
        speech.emit(partial + "。")
        XCTAssertEqual(session.currentCaption?.text, partial + "。")
        await session.stop()
    }

    func testRequestRotationCarriesUnfinishedTextIntoNextRequest() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.emit("今天我们决定")
        speech.utteranceID = UUID()
        speech.emit("等大家准备好以后再出发。")
        XCTAssertEqual(session.currentCaption?.text, "今天我们决定等大家准备好以后再出发。")
        await session.stop()
    }

    func testPauseDiscardsUnfinishedCarry() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.emit("这段没有说完的内容")
        await session.pause()
        await session.start()
        speech.emit("这是一段新的内容。")
        XCTAssertEqual(session.history.map(\.text), ["这是一段新的内容。"])
        await session.stop()
    }

    func testActualFinalPublishesUnpunctuatedUtterance() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.callback?(TranscriptEvent(utteranceID: speech.utteranceID, text: "谢谢你今天过来帮忙", isFinal: true))
        XCTAssertEqual(session.currentCaption?.text, "谢谢你今天过来帮忙")
        await session.stop()
    }

    func testRevisedZeroTimedTranscriptDoesNotReplayOldClauses() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        let original = "他笑着说马上就去安排，大家发现他今天特别高兴，老板也看到了表现的机会，"
        func zeroTiming(_ text: String) -> [SpeechSegment] {
            [SpeechSegment(range: NSRange(location: 0, length: text.utf16.count), startTime: 0, duration: 0)]
        }
        speech.emit(original, segments: zeroTiming(original))
        let previous = session.history
        let revised = "他笑着说马上就去安排，大家发现他今天特别高兴还一直哼着歌，老板也看到了表现的机会，"
        speech.emit(revised, segments: zeroTiming(revised))
        XCTAssertEqual(session.history, previous)
        await session.stop()
    }

    func testHistoryRetainsLatestThreeHundredPhrases() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.emit((1...350).map { "第\($0)句话。" }.joined())
        XCTAssertEqual(session.history.count, 300)
        XCTAssertEqual(session.history.first?.text, "第51句话。")
        XCTAssertEqual(session.history.last?.text, "第350句话。")
        XCTAssertEqual(session.currentCaption?.text, "第350句话。")
        await session.stop()
    }

    func testClearHistoryPreservesCurrentDisplay() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech)
        await session.start()
        speech.emit("当前字幕。")
        let caption = session.currentCaption
        session.clearHistory()
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(session.currentCaption, caption)
        await session.stop()
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
