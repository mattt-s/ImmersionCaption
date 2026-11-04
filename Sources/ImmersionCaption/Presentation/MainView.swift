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
            HStack {
                SessionControls(session: session)
                Spacer()
                LanguagePicker(settings: settings,
                    isEnabled: session.state != .running && !session.isTransitioning)
                    .frame(maxWidth: 320)
            }
            Text("Captions application audio in your selected language, on your Mac. Your microphone is never used.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = session.errorMessage {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            TabView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Captions update as you listen, including corrections to earlier words.")
                        .font(.callout).foregroundStyle(.secondary)
                    HistoryView(session: session)
                }
                .padding(16)
                .tabItem { Label("Captions", systemImage: "text.bubble") }
                SettingsView(settings: settings, session: session)
                    .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            }
        }
        .padding(24)
    }
}
