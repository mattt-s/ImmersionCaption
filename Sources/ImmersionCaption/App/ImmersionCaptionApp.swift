import SwiftUI
import AppKit

@main
@MainActor
struct ImmersionCaptionApp: App {
    @StateObject private var container = AppContainer()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("ImmersionCaption", id: "main") {
            MainView(session: container.session, settings: container.settings)
                .frame(minWidth: 640, minHeight: 560)
                .task { await container.preparePresentation() }
        }
        .defaultSize(width: 760, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        Settings {
            SettingsView(settings: container.settings)
                .padding(24)
                .frame(width: 480)
        }
        MenuBarExtra("ImmersionCaption", systemImage: "captions.bubble") {
            MenuBarView(session: container.session)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
