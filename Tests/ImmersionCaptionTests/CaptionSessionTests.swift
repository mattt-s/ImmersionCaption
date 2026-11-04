import XCTest
import CoreMedia
import CaptionCore
@testable import ImmersionCaption

@MainActor
final class CaptionSessionTests: XCTestCase {
    func testUnpunctuatedDraftAppearsImmediatelyAndRevisionsReplaceIt() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "en-US" })
        await session.start()
        speech.emit("The cargo sheep")
        let original = session.currentCaption
        XCTAssertEqual(original?.text, "The cargo sheep")
        speech.emit("The cargo ship has arrived")
        XCTAssertEqual(session.currentCaption?.text, "The cargo ship has arrived")
        XCTAssertEqual(session.currentCaption?.id, original?.id)
        XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.displayCaptions.count, 1)
        XCTAssertEqual(speech.languages, ["en-US"])
        await session.stop()
    }

    func testFinalUpdatesExistingBlockWithoutWaitingOrDuplicating() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
        await session.start()
        speech.emit("今天我们讨论")
        XCTAssertEqual(session.currentCaption?.text, "今天我们讨论")
        speech.emit("今天我们讨论字幕。", isFinal: true)
        XCTAssertEqual(session.history.count, 1)
        XCTAssertEqual(session.currentCaption?.isFinal, true)
        XCTAssertEqual(session.currentCaption?.text, "今天我们讨论字幕。")
        await session.stop()
    }

    func testPunctuationDoesNotSplitDisplayOrHistory() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
        await session.start()
        speech.emit("一。二。三，四，五。")
        XCTAssertEqual(session.history.map(\.text), ["一。二。三，四，五。"])
        await session.stop()
    }

    func testNewRequestsAccumulateRollingContextAndBoundHistory() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "ja-JP" })
        await session.start()
        for index in 1...305 {
            speech.utteranceID = UUID()
            speech.emit("字幕\(index)")
        }
        XCTAssertEqual(session.history.count, 300)
        XCTAssertEqual(session.history.first?.text, "字幕6")
        XCTAssertEqual(session.displayCaptions.map(\.text), ["字幕303", "字幕304", "字幕305"])
        XCTAssertEqual(session.currentCaption?.languageIdentifier, "ja-JP")
        await session.stop()
    }

    func testLanguageChangesOnResumeAndOldLanguageDoesNotMixIntoDisplay() async {
        let speech = FakeSpeech()
        var language = "zh-CN"
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { language })
        await session.start()
        speech.emit("你好")
        await session.pause()
        XCTAssertNil(session.currentCaption)
        XCTAssertTrue(session.displayCaptions.isEmpty)
        language = "en-US"
        speech.utteranceID = UUID()
        await session.start()
        speech.emit("Hello")
        XCTAssertEqual(speech.languages, ["zh-CN", "en-US"])
        XCTAssertEqual(session.displayCaptions.map(\.text), ["Hello"])
        XCTAssertEqual(session.history.map(\.languageIdentifier), ["zh-CN", "en-US"])
        await session.stop()
    }

    func testUnavailableLanguageFailsBeforeCaptureStarts() async {
        let speech = FakeSpeech()
        let capture = FakeCapture()
        speech.startupError = SpeechError.localModelUnavailable(language: "Japanese")
        let session = CaptionSession(capture: capture, speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "ja-JP" })
        await session.start()
        XCTAssertEqual(session.state, .failed)
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertTrue(session.errorMessage?.contains("Japanese") == true)
    }

    func testClearHistoryDoesNotHideCurrentRollingDisplay() async {
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "en-US" })
        await session.start()
        speech.emit("Hello")
        let current = session.currentCaption
        session.clearHistory()
        XCTAssertTrue(session.history.isEmpty)
        XCTAssertEqual(session.currentCaption, current)
        XCTAssertEqual(session.displayCaptions.map(\.text), ["Hello"])
        speech.emit("Hello again")
        XCTAssertEqual(session.history.map(\.text), ["Hello again"])
        await session.stop()
    }

    func testStopDuringSpeechPermissionCannotStartCaptureLater() async {
        let capture = FakeCapture()
        let speech = FakeSpeech()
        speech.holdStartup = true
        let session = CaptionSession(capture: capture, speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
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
        let session = CaptionSession(capture: FakeCapture(), speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
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
        let session = CaptionSession(capture: capture, speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
        await session.start()
        speech.failure?(SpeechError.localModelUnavailable(language: "Chinese"))
        await waitUntil { session.state == .failed && !session.isTransitioning }
        XCTAssertNotNil(session.errorMessage)
        XCTAssertNil(speech.callback)
        XCTAssertEqual(capture.stopCount, 1)
    }

    func testStopDuringCaptureStartupRejectsLateSuccess() async {
        let capture = FakeCapture()
        capture.holdStartup = true
        let speech = FakeSpeech()
        let session = CaptionSession(capture: capture, speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
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
        let session = CaptionSession(capture: capture, speech: speech, makeActivityMonitor: { FakeAudioActivityMonitor() }, selectedLanguage: { "zh-CN" })
        await session.start()
        capture.holdNextStop = true
        speech.failure?(SpeechError.localModelUnavailable(language: "Chinese"))
        await waitUntil { capture.pendingStop != nil }
        await session.stop()
        capture.pendingStop?.resume()
        await waitUntil { !session.isTransitioning }
        XCTAssertEqual(session.state, .stopped)
        XCTAssertNil(session.errorMessage)
    }


    func testSilenceHidesOverlayAndLateFinalCannotReopenIt() async {
        var clock: TimeInterval = 100
        let activity = FakeAudioActivityMonitor()
        activity.mark(at: clock)
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech,
            makeActivityMonitor: { activity }, selectedLanguage: { "en-US" }, now: { clock })
        await session.start()
        speech.emit("Hello")
        XCTAssertTrue(session.isCaptionVisible)

        // No further buffers or recognition events: the watchdog must still hide the panel.
        clock = 102
        await waitUntil { !session.isCaptionVisible }
        XCTAssertEqual(session.history.first?.text, "Hello")
        speech.emit("Hello.", isFinal: true)
        XCTAssertFalse(session.isCaptionVisible)
        XCTAssertEqual(session.history.first?.text, "Hello.")

        // Resuming output alone must not reveal old text.
        clock = 103
        activity.mark(at: clock)
        await Task.yield()
        XCTAssertFalse(session.isCaptionVisible)
        speech.utteranceID = UUID()
        speech.emit("New speech")
        XCTAssertTrue(session.isCaptionVisible)
        await session.stop()
    }

    func testShortAudioGapsDoNotHideCaptionAndContinuousSoundKeepsItVisible() async throws {
        var clock: TimeInterval = 100
        let activity = FakeAudioActivityMonitor()
        activity.mark(at: clock)
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech,
            makeActivityMonitor: { activity }, selectedLanguage: { "en-US" }, now: { clock })
        await session.start()
        speech.emit("A sentence")
        clock = 100.6
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(session.isCaptionVisible)
        activity.mark(at: clock)
        clock = 101.2
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(session.isCaptionVisible)
        clock = 102
        await waitUntil { !session.isCaptionVisible }
        await session.stop()
    }

    func testNewCaptureRunDoesNotReuseOldAudioActivity() async {
        let old = FakeAudioActivityMonitor(), fresh = FakeAudioActivityMonitor()
        var count = 0
        let speech = FakeSpeech()
        let session = CaptionSession(capture: FakeCapture(), speech: speech,
            makeActivityMonitor: { count += 1; return count == 1 ? old : fresh },
            selectedLanguage: { "en-US" }, now: { 100 })
        old.mark(at: 100)
        await session.start()
        speech.emit("Old speech")
        XCTAssertTrue(session.isCaptionVisible)
        await session.pause()
        XCTAssertFalse(session.isCaptionVisible)
        await session.start()
        old.mark(at: 100)
        speech.utteranceID = UUID()
        speech.emit("Late text before new audio")
        XCTAssertFalse(session.isCaptionVisible)
        fresh.mark(at: 100)
        speech.emit("Actual new speech")
        XCTAssertTrue(session.isCaptionVisible)
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
    var languages: [String] = []
    var startupError: Error?
    var audioReceiver: (CMSampleBuffer) -> Void { { _ in } }
    func start(languageIdentifier: String, onTranscript: @escaping @MainActor (TranscriptEvent) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws {
        languages.append(languageIdentifier)
        callback = onTranscript
        failure = onFailure
        if holdStartup { await withCheckedContinuation { startup = $0 } }
        if let startupError { throw startupError }
    }
    func stop() { callback = nil; failure = nil }
    func emit(_ text: String, isFinal: Bool = false) {
        callback?(TranscriptEvent(utteranceID: utteranceID, text: text, isFinal: isFinal))
    }
}

/// Locking matches the port's capture/MainActor ownership without retaining audio.
private final class FakeAudioActivityMonitor: AudioActivityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?
    var lastAudibleTime: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func mark(at time: TimeInterval) {
        lock.lock(); value = time; lock.unlock()
    }
    func consume(_ sample: CMSampleBuffer) { mark(at: ProcessInfo.processInfo.systemUptime) }
}
