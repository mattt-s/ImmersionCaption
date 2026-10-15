import Foundation
import Combine
import CaptionCore
import OSLog

/// Owns one capture → recognition → translation session and rejects results from old generations.
@MainActor
final class CaptionSession: ObservableObject {
    @Published private(set) var state: SessionState = .stopped
    @Published private(set) var currentCaption: Caption?
    @Published private(set) var history: [Caption] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var droppedPhrases = 0
    @Published private(set) var pendingPhrases = 0
    @Published private(set) var sourceDraft = ""
    @Published private(set) var isTranslating = false
    @Published private(set) var isTransitioning = false

    private let capture: SystemAudioCapturing
    private let speech: SpeechRecognizing
    private let translator: TranslationEngine
    private let logger = Logger(subsystem: "app.ImmersionCaption", category: "Session")
    private var generation = UUID()
    private var segmenter = TranscriptSegmenter()
    private var utteranceID: UUID?
    private var lastHypothesis = ""
    private var queue = BoundedQueue<String>(capacity: 3)
    private var context: [Caption] = []
    private var worker: Task<Void, Never>?
    private var stableDraft: Task<Void, Never>?
    private var expiration: Task<Void, Never>?
    private let stableDelay: UInt64
    private var transitions = 0 {
        didSet { isTransitioning = transitions > 0 }
    }

    init(capture: SystemAudioCapturing, speech: SpeechRecognizing,
         translator: TranslationEngine, stableDelay: UInt64 = 1_000_000_000) {
        self.capture = capture
        self.speech = speech
        self.translator = translator
        self.stableDelay = stableDelay
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
        do {
            try await speech.start(onTranscript: { [weak self] event in
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

    /// Allows users to verify the local model and translation quality without audio permission.
    func translateSample(_ text: String) {
        guard state == .stopped || state == .failed, !isTransitioning else { return }
        let source = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !source.isEmpty, worker == nil else { return }
        errorMessage = nil
        enqueue([source])
    }

    func clearHistory() { history.removeAll(); context.removeAll() }

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
        worker?.cancel(); worker = nil
        stableDraft?.cancel(); stableDraft = nil
        expiration?.cancel(); expiration = nil
        segmenter.reset()
        utteranceID = nil
        lastHypothesis = ""
        sourceDraft = ""
        currentCaption = nil
        context.removeAll()
        queue.removeAll()
        droppedPhrases = 0
        pendingPhrases = 0
        isTranslating = false
    }

    private func receive(_ event: TranscriptEvent) {
        guard state == .running else { return }
        if utteranceID != event.utteranceID {
            enqueue(segmenter.flush())
            segmenter.reset()
            utteranceID = event.utteranceID
            lastHypothesis = ""
        }
        sourceDraft = event.text
        enqueue(segmenter.ingest(event.text, isFinal: event.isFinal))
        guard event.text != lastHypothesis || event.isFinal else { return }
        lastHypothesis = event.text
        stableDraft?.cancel()
        if !event.isFinal {
            let token = generation
            stableDraft = Task { [weak self, stableDelay] in
                do { try await Task.sleep(nanoseconds: stableDelay) } catch { return }
                guard let self, self.generation == token, self.state == .running else { return }
                self.enqueue(self.segmenter.flush())
            }
        }
    }

    private func enqueue(_ phrases: [String]) {
        guard !phrases.isEmpty else { return }
        phrases.forEach { queue.append($0) }
        droppedPhrases = queue.droppedCount
        pendingPhrases = queue.count
        guard worker == nil else { return }
        let token = generation
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == token, let source = self.queue.popFirst() {
                self.pendingPhrases = self.queue.count
                self.isTranslating = true
                do {
                    let translated = try await self.translator.translate(TranslationInput(source: source, context: self.context))
                    guard !Task.isCancelled, self.generation == token else { return }
                    let caption = Caption(source: source, translation: translated)
                    self.currentCaption = caption
                    self.history.append(caption)
                    if self.history.count > 300 { self.history.removeFirst(self.history.count - 300) }
                    self.context = Array((self.context + [caption]).suffix(2))
                    self.scheduleExpiration(caption.id, token: token)
                } catch {
                    guard !Task.isCancelled, self.generation == token else { return }
                    await self.fail(error, token: token)
                    return
                }
            }
            guard self.generation == token else { return }
            self.isTranslating = false
            self.worker = nil
        }
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
