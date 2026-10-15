import SwiftUI

struct SessionControls: View {
    @ObservedObject var session: CaptionSession

    var body: some View {
        HStack(spacing: 12) {
            if session.state == .running {
                Button { Task { await session.pause() } } label: { Label("Pause", systemImage: "pause.fill") }
            } else {
                Button { Task { await session.start() } } label: {
                    Label(session.state == .paused ? "Resume" : "Start translating", systemImage: "play.fill")
                }
                .disabled(!session.state.canStart || session.isTransitioning)
                .keyboardShortcut(.return, modifiers: .command)
            }
            Button { Task { await session.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                .disabled(session.state == .stopped && !session.isTranslating)
            if session.state == .starting || session.isTranslating { ProgressView().controlSize(.small) }
        }
        .buttonStyle(.bordered)
    }
}
