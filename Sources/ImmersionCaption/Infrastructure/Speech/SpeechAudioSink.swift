import Foundation
import Speech
import CoreMedia
import CaptionCore

/// Serializes audio append/endAudio with request replacement. While the old recognizer
/// finishes, retains owning PCM samples in a bounded in-memory buffer for the next request.
final class SpeechAudioSink {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var sessionID: UUID?
    private var requestID: UUID?
    private var hasRecognizedSpeech = false
    private var pauseDetector = SpeechPauseDetector()
    private var lastAudioTime: TimeInterval?
    private let clock: () -> TimeInterval
    private let measure: (CMSampleBuffer) throws -> Double
    private var buffering = false
    private var failed = false
    private struct PendingAudio {
        let sample: CMSampleBuffer
        let rms: Double
        let duration: TimeInterval
    }
    private var pending: [PendingAudio] = []
    private var pendingDuration: TimeInterval = 0
    private let maximumBufferedDuration: TimeInterval
    private let maximumBufferedSamples: Int

    init(maximumBufferedDuration: TimeInterval = 12, maximumBufferedSamples: Int = 2048,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         measure: @escaping (CMSampleBuffer) throws -> Double = { try PCMActivityMeter().rms(of: $0) }) {
        self.maximumBufferedDuration = maximumBufferedDuration
        self.maximumBufferedSamples = maximumBufferedSamples
        self.clock = clock
        self.measure = measure
    }

    /// Replays buffered audio in capture order before allowing new samples to append.
    func start(_ next: SFSpeechAudioBufferRecognitionRequest, sessionID: UUID, requestID: UUID = UUID()) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        if self.sessionID != sessionID {
            pending.removeAll()
            pendingDuration = 0
        }
        self.sessionID = sessionID
        self.requestID = requestID
        hasRecognizedSpeech = false
        pauseDetector.reset()
        lastAudioTime = nil
        request = next
        buffering = false
        failed = false
        for audio in pending {
            // Replay contributes to activity detection, but cannot end the new request
            // before its own recognizer has confirmed speech.
            pauseDetector.observe(rms: audio.rms, duration: audio.duration)
            next.appendAudioSampleBuffer(audio.sample)
        }
        if !pending.isEmpty { lastAudioTime = clock() }
        pending.removeAll()
        pendingDuration = 0
    }

    /// Ends only the old request's input. Capture continues into the temporary buffer.
    func beginFinalization() {
        lock.lock(); defer { lock.unlock() }
        endInput()
    }

    /// Native drafts only confirm that this request contains speech; their text never
    /// supplies a translation or a substring boundary.
    func confirmSpeech(sessionID: UUID, requestID: UUID) {
        lock.lock(); defer { lock.unlock() }
        guard self.sessionID == sessionID, self.requestID == requestID, request != nil else { return }
        hasRecognizedSpeech = true
    }

    /// Atomically ends input at sustained quiet, including a source delivering no buffers.
    /// The caller must still call finish() and await the genuine final callback.
    func endIfPaused(sessionID: UUID, requestID: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard self.sessionID == sessionID, self.requestID == requestID,
              request != nil, !failed, hasRecognizedSpeech, pauseDetector.hasActivity,
              let lastAudioTime else { return false }
        guard pauseDetector.hasPause || clock() - lastAudioTime >= pauseDetector.quietDuration else { return false }
        endInput()
        return true
    }

    /// Call only with lock held; detaching here prevents later capture entering this request.
    private func endInput() {
        guard request != nil else { return }
        request?.endAudio()
        request = nil
        buffering = true
    }

    func stop() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        request = nil
        sessionID = nil
        requestID = nil
        hasRecognizedSpeech = false
        pauseDetector.reset()
        lastAudioTime = nil
        buffering = false
        failed = false
        pending.removeAll()
        pendingDuration = 0
    }

    /// Returns an error once if buffering cannot safely continue. The adapter stops the
    /// session; it must not silently drop buffered speech or translate an earlier draft.
    func append(_ sample: CMSampleBuffer, sessionID: UUID) -> SpeechError? {
        lock.lock(); defer { lock.unlock() }
        guard self.sessionID == sessionID, !failed else { return nil }
        let duration = CMSampleBufferGetDuration(sample).seconds
        guard sample.isValid, duration.isFinite, duration > 0 else {
            failed = true
            return .invalidAudioTiming
        }
        let level: Double
        do { level = try measure(sample) }
        catch {
            failed = true
            return .unsupportedAudioFormat
        }
        if let request {
            pauseDetector.observe(rms: level, duration: duration)
            lastAudioTime = clock()
            request.appendAudioSampleBuffer(sample)
            return nil
        }
        guard buffering else { return nil }
        guard pending.count < maximumBufferedSamples,
              pendingDuration + duration <= maximumBufferedDuration else {
            failed = true
            return .finalizationBufferOverflow
        }
        pending.append(PendingAudio(sample: sample, rms: level, duration: duration))
        pendingDuration += duration
        return nil
    }
}
