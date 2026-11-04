import Foundation

/// Composition root: chooses capture and recognition providers and defers native window creation.
@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettings
    let session: CaptionSession
    private(set) var overlay: SubtitleOverlayController?

    init() {
        let settings = AppSettings(languages: AppleSpeechRecognizer.availableLanguages())
        let session = CaptionSession(capture: CoreAudioTapCapture(), speech: AppleSpeechRecognizer(),
                                     makeActivityMonitor: { PCMActivityMonitor() },
                                     selectedLanguage: { settings.languageIdentifier })
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
