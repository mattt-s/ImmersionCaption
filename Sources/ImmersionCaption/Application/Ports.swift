import CoreMedia
import Foundation

/// Produces application-output audio only. Implementations own permission and stream cleanup.
@MainActor
protocol SystemAudioCapturing: AnyObject {
    func start(receive: @escaping (CMSampleBuffer) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws
    func stop() async
}

/// A complete current hypothesis for one request. New callbacks replace its previous
/// text; only actual recognizer completion marks it final.
struct TranscriptEvent {
    let utteranceID: UUID
    let text: String
    let isFinal: Bool
}

/// Accepts captured audio and emits cumulative hypotheses. No cloud fallback is allowed.
@MainActor
protocol SpeechRecognizing: AnyObject {
    func start(languageIdentifier: String, onTranscript: @escaping @MainActor (TranscriptEvent) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws
    /// This closure must be safe to invoke synchronously from the capture callback queue.
    var audioReceiver: (CMSampleBuffer) -> Void { get }
    func stop()
}
