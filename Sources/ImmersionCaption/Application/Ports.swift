import CoreMedia
import Foundation
import CaptionCore

/// Produces application-output audio only. Implementations own permission and stream cleanup.
@MainActor
protocol SystemAudioCapturing: AnyObject {
    func start(receive: @escaping (CMSampleBuffer) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws
    func stop() async
}

/// A cumulative hypothesis within one recognition request. isFinal means actual recognizer
/// completion; maintenance rotations change the ID without forcing unfinished speech final.
struct TranscriptEvent {
    let utteranceID: UUID
    let text: String
    let isFinal: Bool
    let segments: [SpeechSegment]

    init(utteranceID: UUID, text: String, isFinal: Bool, segments: [SpeechSegment] = []) {
        self.utteranceID = utteranceID
        self.text = text
        self.isFinal = isFinal
        self.segments = segments
    }
}

/// Accepts captured audio and emits cumulative hypotheses. No cloud fallback is allowed.
@MainActor
protocol SpeechRecognizing: AnyObject {
    func start(onTranscript: @escaping @MainActor (TranscriptEvent) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws
    /// This closure must be safe to invoke synchronously from the capture callback queue.
    var audioReceiver: (CMSampleBuffer) -> Void { get }
    func stop()
}

/// An inference backend, independent of HTTP, model names, and the presentation layer.
@MainActor
protocol TranslationEngine: AnyObject {
    func translate(_ input: TranslationInput) async throws -> String
}
