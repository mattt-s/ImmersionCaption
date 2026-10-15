import Foundation
import Speech
import CoreMedia

enum SpeechError: LocalizedError {
    case permissionDenied, localModelUnavailable
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Allow Speech Recognition for ImmersionCaption in System Settings → Privacy & Security. Microphone access is not needed."
        case .localModelUnavailable:
            return "On-device Mandarin recognition is unavailable. Enable/download Mandarin (China mainland) Dictation in System Settings → Keyboard, then retry. Availability depends on macOS and installed language assets. Cloud recognition is disabled."
        }
    }
}

/// Uses Apple's installed Mandarin model and explicitly requires all recognition to stay on-device.
@MainActor
final class AppleSpeechRecognizer: SpeechRecognizing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let sink = SpeechAudioSink()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var rotation: Task<Void, Never>?
    private var sessionID = UUID()
    private var requestID = UUID()
    private var latestText = ""
    private var onTranscript: (@MainActor (TranscriptEvent) -> Void)?
    private var onFailure: (@MainActor (Error) -> Void)?

    var audioReceiver: (CMSampleBuffer) -> Void {
        let sink = sink
        return { sample in sink.append(sample) }
    }

    func start(onTranscript: @escaping @MainActor (TranscriptEvent) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws {
        stop()
        let token = sessionID
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == token else { throw CancellationError() }
        guard status == .authorized else { throw SpeechError.permissionDenied }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw SpeechError.localModelUnavailable
        }
        self.onTranscript = onTranscript
        self.onFailure = onFailure
        beginRequest()
    }

    func stop() {
        sessionID = UUID()
        requestID = UUID()
        rotation?.cancel(); rotation = nil
        sink.replace(with: nil)
        recognitionTask?.cancel(); recognitionTask = nil
        onTranscript = nil
        onFailure = nil
        latestText = ""
    }

    private func beginRequest() {
        guard let recognizer, onTranscript != nil else { return }
        rotation?.cancel()
        requestID = UUID()
        let requestToken = requestID
        let sessionToken = sessionID
        latestText = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        sink.replace(with: request)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Apple may deliver callbacks off-main. Only value data crosses into session state.
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.sessionID == sessionToken, self.requestID == requestToken else { return }
                if let text {
                    self.latestText = text
                    self.onTranscript?(TranscriptEvent(utteranceID: requestToken, text: text, isFinal: final))
                }
                if final {
                    self.recognitionTask?.cancel()
                    self.beginRequest()
                } else if let error {
                    let handler = self.onFailure
                    self.stop()
                    handler?(error)
                }
            }
        }
        // Rotate before legacy recognizer duration limits; flush its last hypothesis first.
        rotation = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 45_000_000_000) } catch { return }
            guard let self, self.sessionID == sessionToken, self.requestID == requestToken else { return }
            self.onTranscript?(TranscriptEvent(utteranceID: requestToken, text: self.latestText, isFinal: true))
            self.recognitionTask?.cancel()
            self.beginRequest()
        }
    }
}

/// Synchronizes request replacement/endAudio with capture callbacks. No audio is stored on disk.
private final class SpeechAudioSink {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request?.endAudio()
        request = next
        lock.unlock()
    }

    func append(_ sample: CMSampleBuffer) {
        lock.lock()
        request?.appendAudioSampleBuffer(sample)
        lock.unlock()
    }
}
