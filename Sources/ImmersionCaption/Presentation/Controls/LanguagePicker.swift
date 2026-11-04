import SwiftUI

/// Explicit spoken-language selection. Active recognition keeps its original locale
/// until paused/stopped, avoiding a silent mid-request language change.
struct LanguagePicker: View {
    @ObservedObject var settings: AppSettings
    let isEnabled: Bool

    var body: some View {
        Picker("Spoken language", selection: $settings.languageIdentifier) {
            if settings.languages.isEmpty {
                Text("No speech languages available").tag("")
            }
            ForEach(settings.languages) { language in
                Text(language.name + (language.supportsOnDeviceRecognition ? "" : " — unavailable on device"))
                    .tag(language.id)
                    .disabled(!language.supportsOnDeviceRecognition)
            }
        }
        .pickerStyle(.menu)
        .disabled(!isEnabled || settings.languages.isEmpty)
        .help(isEnabled ? "Choose the language spoken in the audio." : "Pause or stop captions to change language.")
    }
}
