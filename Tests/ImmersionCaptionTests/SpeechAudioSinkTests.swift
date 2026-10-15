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

    private func makeSamples(count: Int) throws -> [CMSampleBuffer] {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: 48_000, channels: 2, interleaved: true))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        pcm.frameLength = 480
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
