import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Subtitles") {
                Text("Captions follow sentence and clause punctuation. Unfinished speech waits for a boundary or a final recognition result.")
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
                Toggle("Preview subtitle overlay", isOn: $settings.previewOverlay)
            }
        }
        .formStyle(.grouped)
    }
}
