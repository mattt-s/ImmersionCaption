import Foundation
import Combine
import CaptionCore
import OSLog

/// Owns system-audio captions and rejects recognition callbacks from old sessions.
@MainActor
final class CaptionSession: ObservableObject {
    @Published private(set) var state: SessionState = .stopped
    @Published private(set) var currentCaption: Caption?
    @Published private(set) var history: [Caption] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var displayCaptions: [Caption] = []
    @Published private(set) var isTransitioning = false

    private let capture: SystemAudioCapturing
    private let speech: SpeechRecognizing
    private let logger = Logger(subsystem: "app.ImmersionCaption", category: "Session")
    private var generation = UUID()
    private let selectedLanguage: () -> String
    private var activeLanguage = ""
    private var transcript = LiveTranscript()
    private var displayTranscript = LiveTranscript(capacity: 3)
    private var expiration: Task<Void, Never>?
    private var transitions = 0 {
        didSet { isTransitioning = transitions > 0 }
    }

    init(capture: SystemAudioCapturing, speech: SpeechRecognizing, selectedLanguage: @escaping () -> String) {
        self.capture = capture
        self.speech = speech
        self.selectedLanguage = selectedLanguage
    }

    /// Startup is serialized with teardown so a late permission response cannot revive a stopped session.
    func start() async {
        guard state.canStart, !isTransitioning else { return }
        transitions += 1
        defer { transitions -= 1 }
        invalidateWork()
        let token = generation
        state = .starting
        errorMessage = nil
        activeLanguage = selectedLanguage()
        do {
            try await speech.start(languageIdentifier: activeLanguage, onTranscript: { [weak self] event in
                guard let self, self.generation == token else { return }
                self.receive(event)
            }, onFailure: { [weak self] error in
                Task { await self?.fail(error, token: token) }
            })
            guard generation == token else { speech.stop(); return }
            try await capture.start(receive: speech.audioReceiver, onFailure: { [weak self] error in
                Task { await self?.fail(error, token: token) }
            })
            guard generation == token else { await capture.stop(); speech.stop(); return }
            state = .running
            logger.info("Caption session started")
        } catch {
            guard generation == token else { return }
            await fail(error, token: token)
        }
    }

    func pause() async { await end(as: .paused) }
    func stop() async { await end(as: .stopped) }

    func clearHistory() { transcript.removeAll(); history.removeAll() }

    @discardableResult
    private func end(as nextState: SessionState) async -> UUID {
        transitions += 1
        defer { transitions -= 1 }
        // Invalidate first, even if startup is waiting for permission.
        invalidateWork()
        let token = generation
        state = nextState
        speech.stop()
        await capture.stop()
        logger.info("Caption session ended")
        return token
    }

    private func fail(_ error: Error, token: UUID) async {
        guard generation == token else { return }
        let failureToken = await end(as: .failed)
        guard generation == failureToken, state == .failed else { return }
        errorMessage = error.localizedDescription
        logger.error("Caption session failed; details shown in UI")
    }

    private func invalidateWork() {
        generation = UUID()
        expiration?.cancel(); expiration = nil
        displayTranscript.removeAll()
        displayCaptions = []
        currentCaption = nil
    }

    /// Replace the active request snapshot on every partial, including earlier-word
    /// corrections. No punctuation, stability delay, or final-result gate is applied.
    private func receive(_ event: TranscriptEvent) {
        guard state == .running else { return }
        guard transcript.update(requestID: event.utteranceID, text: event.text,
                                languageIdentifier: activeLanguage, isFinal: event.isFinal) else { return }
        history = transcript.captions
        // Retain recent request context for a rolling display, bounded independently of history.
        displayTranscript.update(requestID: event.utteranceID, text: event.text,
                                 languageIdentifier: activeLanguage, isFinal: event.isFinal)
        displayCaptions = displayTranscript.captions
        currentCaption = displayCaptions.last
        if let caption = currentCaption { scheduleExpiration(caption.id, token: generation) }
    }

    private func scheduleExpiration(_ captionID: UUID, token: UUID) {
        expiration?.cancel()
        expiration = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { return }
            guard let self, self.generation == token, self.currentCaption?.id == captionID else { return }
            self.currentCaption = nil
        }
    }
}
