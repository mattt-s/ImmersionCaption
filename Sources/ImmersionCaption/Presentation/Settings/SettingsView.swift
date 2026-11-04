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
                Picker("Position", selection: Binding(get: { settings.positionIdentifier }, set: { value in
                    if let preset = SubtitlePosition(rawValue: value) { settings.selectPositionPreset(preset) }
                })) {
                    ForEach(SubtitlePosition.allCases) { Text($0.title).tag($0.rawValue) }
                    if settings.placement.custom != nil { Text("Custom").tag("custom") }
                }
                Button(settings.isOverlayLocked ? "Unlock and move captions" : "Lock caption position") {
                    settings.isOverlayLocked.toggle()
                }
                Text("Unlock to drag the handle in the caption window. Lock to keep the position and restore normal behavior.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("When locked, captions and background hide after a short silence and return with newly recognized speech. Unlocking keeps the window visible for positioning.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Click-through overlay", isOn: $settings.clickThrough)
                Text("Click-through resumes when you lock the position. The corner lock button remains clickable. Turn off click-through to scroll back or pause Follow live.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Preview subtitle overlay", isOn: $settings.previewOverlay)
            }
        }
        .formStyle(.grouped)
    }
}
