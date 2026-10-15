import Foundation
import Speech
import CoreMedia

/// Uses Apple's installed Mandarin model and explicitly requires all recognition to stay on-device.
@MainActor
final class AppleSpeechRecognizer: SpeechRecognizing {
    /// Scalar diagnostic only; never stores or logs recognized content.
    private(set) var pauseFinalizationCount = 0
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let sink = SpeechAudioSink()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var rotation: Task<Void, Never>?
    private var pauseMonitor: Task<Void, Never>?
    private var finalizationTimeout: Task<Void, Never>?
    private var isFinishing = false
    private var sessionID = UUID()
    private var requestID = UUID()
    private var onTranscript: (@MainActor (TranscriptEvent) -> Void)?
    private var onFailure: (@MainActor (Error) -> Void)?

    var audioReceiver: (CMSampleBuffer) -> Void {
        let sink = sink
        let token = sessionID
        return { [weak self] sample in
            if let error = sink.append(sample, sessionID: token) {
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == token else { return }
                    self.fail(error)
                }
            }
        }
    }

    func start(onTranscript: @escaping @MainActor (TranscriptEvent) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws {
        stop()
        pauseFinalizationCount = 0
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
        pauseMonitor?.cancel(); pauseMonitor = nil
        finalizationTimeout?.cancel(); finalizationTimeout = nil
        isFinishing = false
        sink.stop()
        recognitionTask?.cancel(); recognitionTask = nil
        onTranscript = nil
        onFailure = nil
    }

    private func beginRequest() {
        guard let recognizer, onTranscript != nil else { return }
        rotation?.cancel()
        pauseMonitor?.cancel()
        requestID = UUID()
        finalizationTimeout?.cancel(); finalizationTimeout = nil
        isFinishing = false
        let requestToken = requestID
        let sessionToken = sessionID
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        sink.start(request, sessionID: sessionID, requestID: requestToken)
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Apple may deliver callbacks off-main. Only value data crosses into session state.
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, self.sessionID == sessionToken, self.requestID == requestToken else { return }
                if let text {
                    if !final, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.sink.confirmSpeech(sessionID: sessionToken, requestID: requestToken)
                    }
                    self.onTranscript?(TranscriptEvent(utteranceID: requestToken, text: text, isFinal: final))
                }
                if final {
                    self.finalizationTimeout?.cancel()
                    self.sink.beginFinalization()
                    self.recognitionTask = nil
                    self.beginRequest()
                } else if let error {
                    self.fail(error)
                }
            }
        }
        // Poll bounded scalar state instead of creating a MainActor task for every
        // audio buffer. The sink closes input atomically with capture delivery.
        pauseMonitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self, self.sessionID == sessionToken, self.requestID == requestToken,
                      !self.isFinishing else { return }
                if self.sink.endIfPaused(sessionID: sessionToken, requestID: requestToken) {
                    self.pauseFinalizationCount += 1
                    self.finishRequest()
                    return
                }
            }
        }
        // Finish before legacy request limits. Do not cancel/restart until Apple
        // delivers an actual final result; new capture is buffered during this wait.
        rotation = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 45_000_000_000) } catch { return }
            guard let self, self.sessionID == sessionToken, self.requestID == requestToken else { return }
            self.finishRequest()
        }
    }

    private func finishRequest() {
        guard !isFinishing, recognitionTask != nil else { return }
        isFinishing = true
        rotation?.cancel(); rotation = nil
        pauseMonitor?.cancel(); pauseMonitor = nil
        sink.beginFinalization()
        recognitionTask?.finish()
        let sessionToken = sessionID
        let requestToken = requestID
        finalizationTimeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, self.sessionID == sessionToken, self.requestID == requestToken,
                  self.isFinishing else { return }
            self.fail(SpeechError.finalizationTimedOut)
        }
    }

    private func fail(_ error: Error) {
        let handler = onFailure
        stop()
        handler?(error)
    }
}
