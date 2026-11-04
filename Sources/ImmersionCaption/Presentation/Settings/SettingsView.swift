import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var session: CaptionSession

    var body: some View {
        Form {
            Section("Recognition") {
                LanguagePicker(settings: settings,
                    isEnabled: session.state != .running && !session.isTransitioning)
                Text("Pause or stop to change language. Language data must be available on this Mac; install missing languages in macOS Dictation settings, then reopen the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Subtitles") {
                Text("Words appear as they are recognized and may be corrected. The caption window scrolls to keep new speech visible.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Font size")
                    Slider(value: $settings.fontSize, in: 16...52, step: 1)
                    Text("\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 48)
                }
                HStack {
                    Text("Background")
                    Slider(value: $settings.opacity, in: 0.2...1)
                    Text("\(Int(settings.opacity * 100))%").monospacedDigit().frame(width: 48)
                }
                Picker("Position", selection: $settings.position) {
                    ForEach(SubtitlePosition.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Keep captions onscreen while running", isOn: $settings.keepOnscreen)
                Toggle("Click-through overlay", isOn: $settings.clickThrough)
                Text("Turn off click-through to scroll back or pause Follow live in the caption window.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Preview subtitle overlay", isOn: $settings.previewOverlay)
            }
        }
        .formStyle(.grouped)
    }
}
