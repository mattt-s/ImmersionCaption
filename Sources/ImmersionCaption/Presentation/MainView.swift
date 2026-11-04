import SwiftUI

struct MainView: View {
    @ObservedObject var session: CaptionSession
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Image(systemName: "captions.bubble.fill").font(.system(size: 36)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ImmersionCaption").font(.largeTitle.bold())
                    Text("Live captions for application audio.").foregroundStyle(.secondary)
                }
                Spacer()
                Text(session.state.rawValue.capitalized)
                    .font(.caption.weight(.semibold)).padding(8)
                    .background(.quaternary, in: Capsule())
            }
            SessionControls(session: session)
            Text("Recognizes Mandarin in application audio on your Mac. Your microphone is never used.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = session.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            TabView {
                VStack(alignment: .leading, spacing: 16) {
                    if !session.sourceDraft.isEmpty {
                        Text("Hearing: \(session.sourceDraft)")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(3)
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
