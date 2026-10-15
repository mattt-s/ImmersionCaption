import SwiftUI

struct MainView: View {
    @ObservedObject var session: CaptionSession
    @ObservedObject var settings: AppSettings
    @State private var sample = "别着急，咱们一步一步来。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: "captions.bubble.fill").font(.system(size: 36)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ImmersionCaption").font(.largeTitle.bold())
                    Text("Everyday Chinese. Natural English.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(session.state.rawValue.capitalized)
                    .font(.caption.weight(.semibold)).padding(8)
                    .background(.quaternary, in: Capsule())
            }
            SessionControls(session: session)
            Text("Captures application audio, using on-device Mandarin recognition and local translation. Your microphone is never used.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = session.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if session.droppedPhrases > 0 {
                Text("Skipped \(session.droppedPhrases) queued phrases to keep up. Pause other audio or use shorter speech if this continues.")
                    .font(.caption).foregroundStyle(.orange)
            }
            TabView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Check local translation") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Enter a short Chinese phrase", text: $sample)
                                .textFieldStyle(.roundedBorder)
                            Button("Translate sample") { session.translateSample(sample) }
                                .disabled(session.state == .running || session.state == .starting || session.state == .paused || session.isTranslating)
                            Text("Use this before starting audio capture to check that Ollama and the model are ready.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                    if !session.sourceDraft.isEmpty {
                        Text("Hearing: \(session.sourceDraft)").font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    }
                    HistoryView(session: session)
                }
                .padding(16)
                .tabItem { Label("Captions", systemImage: "text.bubble") }
                SettingsView(settings: settings)
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
        }
        .padding(24)
    }
}
