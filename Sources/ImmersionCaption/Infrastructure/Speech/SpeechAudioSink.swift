import Foundation
import Speech
import CoreMedia

/// Serializes audio append/endAudio with request replacement. While the old recognizer
/// finishes, retains owning PCM samples in a bounded in-memory buffer for the next request.
final class SpeechAudioSink {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var sessionID: UUID?
    private var buffering = false
    private var failed = false
    private var pending: [CMSampleBuffer] = []
    private var pendingDuration: TimeInterval = 0
    private let maximumBufferedDuration: TimeInterval
    private let maximumBufferedSamples: Int

    init(maximumBufferedDuration: TimeInterval = 12, maximumBufferedSamples: Int = 2048) {
        self.maximumBufferedDuration = maximumBufferedDuration
        self.maximumBufferedSamples = maximumBufferedSamples
    }

    /// Replays buffered audio in capture order before allowing new samples to append.
    func start(_ next: SFSpeechAudioBufferRecognitionRequest, sessionID: UUID) {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio()
        if self.sessionID != sessionID {
            pending.removeAll()
            pendingDuration = 0
        }
        self.sessionID = sessionID
        request = next
        buffering = false
        failed = false
        for sample in pending { next.appendAudioSampleBuffer(sample) }
        pending.removeAll()
        pendingDuration = 0
    }

    /// Ends only the old request's input. Capture continues into the temporary buffer.
    func beginFinalization() {
        lock.lock(); defer { lock.unlock() }
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
        if let request { request.appendAudioSampleBuffer(sample); return nil }
        guard buffering else { return nil }
        let duration = CMSampleBufferGetDuration(sample).seconds
        guard sample.isValid, duration.isFinite, duration > 0 else {
            failed = true
            return .invalidAudioTiming
        }
        guard pending.count < maximumBufferedSamples,
              pendingDuration + duration <= maximumBufferedDuration else {
            failed = true
            return .finalizationBufferOverflow
        }
        pending.append(sample)
        pendingDuration += duration
        return nil
    }
}
