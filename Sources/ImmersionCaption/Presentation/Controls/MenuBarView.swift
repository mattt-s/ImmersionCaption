import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject var session: CaptionSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("ImmersionCaption · \(session.state.rawValue.capitalized)")
        if session.state == .running {
            Button("Pause") { Task { await session.pause() } }
        } else {
            Button(session.state == .paused ? "Resume" : "Start captions") { Task { await session.start() } }
                .disabled(!session.state.canStart || session.isTransitioning)
        }
        Button("Stop") { Task { await session.stop() } }
        Divider()
        Button("Open ImmersionCaption") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit ImmersionCaption") {
            Task { await session.stop(); NSApp.terminate(nil) }
        }.keyboardShortcut("q")
    }
}
