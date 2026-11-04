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
    @Published private(set) var isCaptionVisible = false

    private let capture: SystemAudioCapturing
    private let speech: SpeechRecognizing
    private let logger = Logger(subsystem: "app.ImmersionCaption", category: "Session")
    private var generation = UUID()
    private let selectedLanguage: () -> String
    private var activeLanguage = ""
    private var transcript = LiveTranscript()
    private var displayTranscript = LiveTranscript(capacity: 3)
    private let makeActivityMonitor: () -> AudioActivityMonitoring
    private let now: () -> TimeInterval
    private let silenceInterval: TimeInterval
    private var activityMonitor: AudioActivityMonitoring?
    private var visibilityTask: Task<Void, Never>?
    private var transitions = 0 {
        didSet { isTransitioning = transitions > 0 }
    }

    init(capture: SystemAudioCapturing, speech: SpeechRecognizing,
         makeActivityMonitor: @escaping () -> AudioActivityMonitoring,
         selectedLanguage: @escaping () -> String,
         silenceInterval: TimeInterval = 1,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.capture = capture
        self.speech = speech
        self.selectedLanguage = selectedLanguage
        self.makeActivityMonitor = makeActivityMonitor
        self.silenceInterval = silenceInterval
        self.now = now
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
            let activity = makeActivityMonitor()
            activityMonitor = activity
            let speechReceiver = speech.audioReceiver
            try await capture.start(receive: { sample in
                activity.consume(sample)
                speechReceiver(sample)
            }, onFailure: { [weak self] error in
                Task { await self?.fail(error, token: token) }
            })
            guard generation == token else { await capture.stop(); speech.stop(); return }
            state = .running
            monitorVisibility(token: token)
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
        visibilityTask?.cancel(); visibilityTask = nil
        activityMonitor = nil
        isCaptionVisible = false
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
        // Late finals/revisions may update history in silence, but cannot reopen the panel.
        isCaptionVisible = !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasRecentAudio
    }

    private var hasRecentAudio: Bool {
        guard let last = activityMonitor?.lastAudibleTime else { return false }
        let elapsed = now() - last
        return elapsed >= 0 && elapsed < silenceInterval
    }

    /// One bounded polling task handles both silent PCM and stopped callbacks. It never
    /// finalizes/restarts recognition and never makes old captions visible on sound alone.
    private func monitorVisibility(token: UUID) {
        visibilityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self, self.generation == token, self.state == .running else { return }
                if self.isCaptionVisible && !self.hasRecentAudio { self.isCaptionVisible = false }
            }
        }
    }
}
