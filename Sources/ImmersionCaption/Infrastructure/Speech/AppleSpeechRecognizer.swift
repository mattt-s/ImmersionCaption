import Foundation
import Speech
import CoreMedia

enum SpeechError: LocalizedError {
    case permissionDenied
    case localModelUnavailable(language: String)
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Allow Speech Recognition for ImmersionCaption in System Settings → Privacy & Security. Microphone access is not needed."
        case .localModelUnavailable(let language):
            return "On-device recognition for \(language) is unavailable. Install the language in System Settings → Keyboard → Dictation, then retry. Availability depends on macOS and installed assets. Cloud recognition is disabled."
        }
    }
}

/// Uses the selected Apple speech locale and requires all recognition to stay on-device.
@MainActor
final class AppleSpeechRecognizer: SpeechRecognizing {
    private var recognizer: SFSpeechRecognizer?
    private let sink = SpeechAudioSink()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var rotation: Task<Void, Never>?
    private var sessionID = UUID()
    private var requestID = UUID()
    private var onTranscript: (@MainActor (TranscriptEvent) -> Void)?
    private var onFailure: (@MainActor (Error) -> Void)?

    /// Enumerates Apple-supported locales; capability is a hint, rechecked at start.
    static func availableLanguages() -> [RecognitionLanguage] {
        SFSpeechRecognizer.supportedLocales().map { locale in
            RecognitionLanguage(id: locale.identifier,
                name: Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier,
                supportsOnDeviceRecognition: SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var audioReceiver: (CMSampleBuffer) -> Void {
        let sink = sink
        return { sample in sink.append(sample) }
    }

    func start(languageIdentifier: String, onTranscript: @escaping @MainActor (TranscriptEvent) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws {
        stop()
        guard !languageIdentifier.isEmpty else {
            throw SpeechError.localModelUnavailable(language: "the selected language")
        }
        let token = sessionID
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard sessionID == token else { throw CancellationError() }
        guard status == .authorized else { throw SpeechError.permissionDenied }
        let locale = Locale(identifier: languageIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            let name = Locale.current.localizedString(forIdentifier: languageIdentifier) ?? languageIdentifier
            throw SpeechError.localModelUnavailable(language: name)
        }
        self.recognizer = recognizer
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
    }

    private func beginRequest() {
        guard let recognizer, onTranscript != nil else { return }
        rotation?.cancel()
        requestID = UUID()
        let requestToken = requestID
        let sessionToken = sessionID
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        sink.replace(with: request)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Apple may deliver callbacks off-main. Only value data crosses into session state.
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.sessionID == sessionToken, self.requestID == requestToken else { return }
                if let text {
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
        // Rotate before legacy limits. The last snapshot remains in history;
        // a new request starts a separate live block without fabricating finality.
        rotation = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 45_000_000_000) } catch { return }
            guard let self, self.sessionID == sessionToken, self.requestID == requestToken else { return }
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
