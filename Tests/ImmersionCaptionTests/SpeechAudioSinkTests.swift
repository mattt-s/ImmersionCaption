import XCTest
import Speech
import AVFoundation
import CoreMedia
@testable import ImmersionCaption

final class SpeechAudioSinkTests: XCTestCase {
    func testFinalizationBuffersAudioAndNextRequestReplaysItInOrder() throws {
        let sink = SpeechAudioSink()
        let token = UUID()
        let old = RecordingRequest()
        let next = RecordingRequest()
        let samples = try makeSamples(count: 4)
        sink.start(old, sessionID: token)
        XCTAssertNil(sink.append(samples[0], sessionID: token))
        sink.beginFinalization()
        XCTAssertNil(sink.append(samples[1], sessionID: token))
        XCTAssertNil(sink.append(samples[2], sessionID: token))
        XCTAssertEqual(old.times, [0])
        XCTAssertEqual(old.endCount, 1)
        sink.start(next, sessionID: token)
        XCTAssertNil(sink.append(samples[3], sessionID: token))
        XCTAssertEqual(next.times.count, 3)
        for (index, time) in next.times.enumerated() {
            XCTAssertEqual(time, Double(index + 1) * 0.01, accuracy: 0.000_001)
        }
        sink.stop()
    }

    func testStopDiscardsBufferedAudioAndRejectsAnOldSessionReceiver() throws {
        let sink = SpeechAudioSink()
        let oldToken = UUID()
        let newToken = UUID()
        let sample = try makeSamples(count: 1)[0]
        sink.start(RecordingRequest(), sessionID: oldToken)
        sink.beginFinalization()
        XCTAssertNil(sink.append(sample, sessionID: oldToken))
        sink.stop()
        let next = RecordingRequest()
        sink.start(next, sessionID: newToken)
        XCTAssertTrue(next.times.isEmpty)
        XCTAssertNil(sink.append(sample, sessionID: oldToken))
        XCTAssertTrue(next.times.isEmpty)
        XCTAssertNil(sink.append(sample, sessionID: newToken))
        XCTAssertEqual(next.times.count, 1)
        sink.stop()
    }

    func testDurationLimitReportsFailureOnceInsteadOfGrowingBuffer() throws {
        let sink = SpeechAudioSink(maximumBufferedDuration: 0.015)
        let token = UUID()
        let samples = try makeSamples(count: 3)
        sink.start(RecordingRequest(), sessionID: token)
        sink.beginFinalization()
        XCTAssertNil(sink.append(samples[0], sessionID: token))
        guard case .finalizationBufferOverflow? = sink.append(samples[1], sessionID: token) else {
            return XCTFail("Expected bounded-buffer failure")
        }
        XCTAssertNil(sink.append(samples[2], sessionID: token))
        sink.stop()
    }

    func testSampleCountLimitIsIndependentOfDurationLimit() throws {
        let sink = SpeechAudioSink(maximumBufferedSamples: 1)
        let token = UUID()
        let sample = try makeSamples(count: 1)[0]
        sink.start(RecordingRequest(), sessionID: token)
        sink.beginFinalization()
        XCTAssertNil(sink.append(sample, sessionID: token))
        guard case .finalizationBufferOverflow? = sink.append(sample, sessionID: token) else {
            return XCTFail("Expected sample-count limit")
        }
        sink.stop()
    }

    func testRepeatedBeginFinalizationDoesNotLoseBufferedAudio() throws {
        let sink = SpeechAudioSink()
        let token = UUID()
        let sample = try makeSamples(count: 1)[0]
        let old = RecordingRequest()
        sink.start(old, sessionID: token)
        sink.beginFinalization()
        XCTAssertNil(sink.append(sample, sessionID: token))
        sink.beginFinalization()
        let next = RecordingRequest()
        sink.start(next, sessionID: token)
        XCTAssertEqual(next.times.count, 1)
        XCTAssertEqual(old.endCount, 1)
        sink.stop()
    }

    func testInvalidBufferedSampleReportsFailureOnce() throws {
        let sink = SpeechAudioSink()
        let token = UUID()
        let sample = try makeSamples(count: 1)[0]
        CMSampleBufferInvalidate(sample)
        sink.start(RecordingRequest(), sessionID: token)
        sink.beginFinalization()
        guard case .invalidAudioTiming? = sink.append(sample, sessionID: token) else {
            return XCTFail("Invalid samples must not enter the handoff buffer")
        }
        XCTAssertNil(sink.append(sample, sessionID: token))
        sink.stop()
    }

    func testPauseClosesInputAndBuffersNextSpeechUntilFinalizedRequestIsReplaced() throws {
        var now: TimeInterval = 0
        var level = 0.1
        let sink = SpeechAudioSink(clock: { now }, measure: { _ in level })
        let session = UUID(), request = UUID()
        let old = RecordingRequest()
        let samples = try makeSamples(count: 130)
        sink.start(old, sessionID: session, requestID: request)
        sink.confirmSpeech(sessionID: session, requestID: request)
        for sample in samples.prefix(20) { _ = sink.append(sample, sessionID: session); now += 0.01 }
        level = 0
        for sample in samples[20..<119] { _ = sink.append(sample, sessionID: session); now += 0.01 }
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        _ = sink.append(samples[119], sessionID: session)
        XCTAssertTrue(sink.endIfPaused(sessionID: session, requestID: request))
        XCTAssertEqual(old.endCount, 1)
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        level = 0.1
        _ = sink.append(samples[120], sessionID: session)
        _ = sink.append(samples[121], sessionID: session)
        XCTAssertEqual(old.times.count, 120)
        let next = RecordingRequest()
        sink.start(next, sessionID: session)
        XCTAssertEqual(next.times.count, 2)
        XCTAssertEqual(next.times[0], 1.2, accuracy: 0.000_001)
        XCTAssertEqual(next.times[1], 1.21, accuracy: 0.000_001)
        sink.stop()
    }

    func testMissingCallbacksAfterRecognizedSpeechAlsoFinishWithoutWaitingFortyFiveSeconds() throws {
        var now: TimeInterval = 0
        let sink = SpeechAudioSink(clock: { now }, measure: { _ in 0.1 })
        let session = UUID(), request = UUID()
        sink.start(RecordingRequest(), sessionID: session, requestID: request)
        for sample in try makeSamples(count: 20) { _ = sink.append(sample, sessionID: session) }
        sink.confirmSpeech(sessionID: session, requestID: request)
        now = 0.99
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        now = 1
        XCTAssertTrue(sink.endIfPaused(sessionID: session, requestID: request))
        sink.stop()
    }

    func testQuietWaitsForItsOwnRecognizedSpeechAndRejectsRetiredRequestTokens() throws {
        var now: TimeInterval = 0
        let sink = SpeechAudioSink(clock: { now }, measure: { _ in 0.1 })
        let session = UUID(), request = UUID()
        sink.start(RecordingRequest(), sessionID: session, requestID: request)
        for sample in try makeSamples(count: 20) { _ = sink.append(sample, sessionID: session) }
        now = 2
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        sink.confirmSpeech(sessionID: session, requestID: UUID())
        sink.confirmSpeech(sessionID: UUID(), requestID: request)
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        sink.confirmSpeech(sessionID: session, requestID: request)
        XCTAssertFalse(sink.endIfPaused(sessionID: UUID(), requestID: request))
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: UUID()))
        XCTAssertTrue(sink.endIfPaused(sessionID: session, requestID: request))
        sink.stop()
    }

    func testResumedAudioCancelsQuietAndReplacementResetsSpeechConfirmation() throws {
        var now: TimeInterval = 0
        let sink = SpeechAudioSink(clock: { now }, measure: { _ in 0.1 })
        let session = UUID(), request = UUID(), nextRequest = UUID()
        let samples = try makeSamples(count: 20)
        sink.start(RecordingRequest(), sessionID: session, requestID: request)
        sink.confirmSpeech(sessionID: session, requestID: request)
        for sample in samples { _ = sink.append(sample, sessionID: session) }
        now = 0.9
        _ = sink.append(samples[0], sessionID: session)
        now = 1.1
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        sink.beginFinalization()
        for sample in samples { _ = sink.append(sample, sessionID: session) }
        sink.start(RecordingRequest(), sessionID: session, requestID: nextRequest)
        now = 3
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: nextRequest))
        sink.confirmSpeech(sessionID: session, requestID: request)
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: nextRequest))
        sink.confirmSpeech(sessionID: session, requestID: nextRequest)
        XCTAssertTrue(sink.endIfPaused(sessionID: session, requestID: nextRequest))
        sink.stop()
    }

    func testInitialSilenceCannotEndEvenWithAnUnexpectedDraft() throws {
        var now: TimeInterval = 0
        let sink = SpeechAudioSink(clock: { now }, measure: { _ in 0 })
        let session = UUID(), request = UUID()
        sink.start(RecordingRequest(), sessionID: session, requestID: request)
        sink.confirmSpeech(sessionID: session, requestID: request)
        for sample in try makeSamples(count: 120) { _ = sink.append(sample, sessionID: session) }
        now = 10
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        sink.stop()
    }

    func testInvalidActivePCMStopsInsteadOfMistakingItForSilence() throws {
        let sink = SpeechAudioSink(measure: { _ in throw SpeechError.unsupportedAudioFormat })
        let session = UUID(), request = UUID()
        sink.start(RecordingRequest(), sessionID: session, requestID: request)
        let sample = try makeSamples(count: 1)[0]
        guard case .unsupportedAudioFormat? = sink.append(sample, sessionID: session) else {
            return XCTFail("Expected a visible audio format error")
        }
        XCTAssertNil(sink.append(sample, sessionID: session))
        XCTAssertFalse(sink.endIfPaused(sessionID: session, requestID: request))
        sink.stop()
    }

    private func makeSamples(count: Int) throws -> [CMSampleBuffer] {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: 48_000, channels: 2, interleaved: true))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        pcm.frameLength = 480
        for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
            memset(buffer.mData, 0, Int(buffer.mDataByteSize))
        }
        let converter = try PCMBufferConverter(format: format.streamDescription.pointee)
        return try (0..<count).map { _ in try XCTUnwrap(converter.convert(pcm.audioBufferList)) }
    }
}

/// Overrides native request delivery so no recognition task, model, or permission is used.
private final class RecordingRequest: SFSpeechAudioBufferRecognitionRequest {
    var times: [TimeInterval] = []
    var endCount = 0
    override func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        times.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
    }
    override func endAudio() { endCount += 1 }
}
