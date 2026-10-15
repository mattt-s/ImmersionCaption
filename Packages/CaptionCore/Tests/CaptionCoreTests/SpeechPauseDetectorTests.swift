import XCTest
@testable import CaptionCore

final class SpeechPauseDetectorTests: XCTestCase {
    func testLeadingSilenceAndShortClicksDoNotBecomeSpeechPauses() {
        var detector = SpeechPauseDetector()
        detector.observe(rms: 0, duration: 10)
        XCTAssertFalse(detector.hasPause)
        detector.observe(rms: 0.2, duration: 0.01)
        detector.observe(rms: 0, duration: 2)
        XCTAssertFalse(detector.hasActivity)
        XCTAssertFalse(detector.hasPause)
    }

    func testOneSecondOfQuietAfterActivityEndsAtThreshold() {
        var detector = SpeechPauseDetector()
        detector.observe(rms: 0.1, duration: 0.2)
        detector.observe(rms: 0, duration: 0.99)
        XCTAssertTrue(detector.hasActivity)
        XCTAssertFalse(detector.hasPause)
        detector.observe(rms: 0, duration: 0.01)
        XCTAssertTrue(detector.hasPause)
    }

    func testBriefWordGapsCannotAccumulateAcrossResumedSpeech() {
        var detector = SpeechPauseDetector()
        for _ in 0..<10 {
            detector.observe(rms: 0.1, duration: 0.2)
            detector.observe(rms: 0, duration: 0.3)
            XCTAssertFalse(detector.hasPause)
        }
    }

    func testLoudBackgroundAudioDoesNotCountAsQuiet() {
        var detector = SpeechPauseDetector()
        detector.observe(rms: 0.1, duration: 0.2)
        detector.observe(rms: 0.02, duration: 30)
        XCTAssertFalse(detector.hasPause)
    }

    func testDecisionsAreIndependentOfBufferSize() {
        var large = SpeechPauseDetector()
        var small = SpeechPauseDetector()
        large.observe(rms: 0.1, duration: 0.2)
        large.observe(rms: 0, duration: 1)
        for _ in 0..<20 { small.observe(rms: 0.1, duration: 0.01) }
        for _ in 0..<100 { small.observe(rms: 0, duration: 0.01) }
        XCTAssertTrue(small.hasPause)
        XCTAssertEqual(large.hasPause, small.hasPause)
    }

    func testInvalidMeasurementsCannotCreateAnEndpoint() {
        var detector = SpeechPauseDetector()
        detector.observe(rms: 0.1, duration: 0.2)
        detector.observe(rms: 0, duration: 0.9)
        detector.observe(rms: .nan, duration: 10)
        XCTAssertFalse(detector.hasPause)
        detector.observe(rms: 0, duration: -.infinity)
        XCTAssertFalse(detector.hasPause)
    }

    func testResetRequiresFreshActivityAndQuiet() {
        var detector = SpeechPauseDetector()
        detector.observe(rms: 0.1, duration: 1)
        detector.observe(rms: 0, duration: 1)
        XCTAssertTrue(detector.hasPause)
        detector.reset()
        detector.observe(rms: 0, duration: 2)
        XCTAssertFalse(detector.hasActivity)
        XCTAssertFalse(detector.hasPause)
    }
}
