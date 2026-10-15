import Foundation

/// Composition root: the only place that chooses concrete capture, recognition, and AI providers.
@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettings
    let session: CaptionSession
    private(set) var overlay: SubtitleOverlayController?

    init() {
        let settings = AppSettings()
        let translator = OllamaTranslationEngine(endpoint: { settings.endpoint }, model: { settings.model })
        let session = CaptionSession(capture: CoreAudioTapCapture(), speech: AppleSpeechRecognizer(),
                                     translator: translator, captionLength: { settings.captionLength })
        self.settings = settings
        self.session = session
    }

    /// Waits until the first view task runs so a second hosting graph is not constructed
    /// while SwiftUI is still resolving the application's StateObject dependencies.
    func preparePresentation() async {
        await Task.yield()
        guard overlay == nil else { return }
        overlay = SubtitleOverlayController(session: session, settings: settings)
    }
}
