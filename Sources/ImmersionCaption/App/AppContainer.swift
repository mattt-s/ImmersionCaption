import Foundation

/// Composition root: the only place that chooses concrete capture, recognition, and AI providers.
@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettings
    let session: CaptionSession
    let overlay: SubtitleOverlayController

    init() {
        let settings = AppSettings()
        let translator = OllamaTranslationEngine(endpoint: { settings.endpoint }, model: { settings.model })
        let session = CaptionSession(capture: ScreenAudioCapture(), speech: AppleSpeechRecognizer(), translator: translator)
        self.settings = settings
        self.session = session
        overlay = SubtitleOverlayController(session: session, settings: settings)
    }
}
