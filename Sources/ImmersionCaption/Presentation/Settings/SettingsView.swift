import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Subtitles") {
                Text("Translations wait for finalized speech. Hearing shows a live draft that may change before subtitles appear.")
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
                Toggle("Show Chinese alongside English", isOn: $settings.bilingual)
                Toggle("Preview subtitle overlay", isOn: $settings.previewOverlay)
            }
            Section("Local translation") {
                TextField("Ollama address", text: $settings.endpoint)
                TextField("Model", text: $settings.model)
                Text("Default: translategemma:4b. Only local addresses are accepted. Changes apply to the next translation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
