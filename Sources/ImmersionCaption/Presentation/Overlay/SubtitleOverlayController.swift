import AppKit
import SwiftUI
import Combine

/// A nonactivating rolling caption panel with optional click-through, visible across Spaces.
@MainActor
final class SubtitleOverlayController {
    private let panel: NSPanel
    private let settings: AppSettings
    private var subscriptions = Set<AnyCancellable>()

    init(session: CaptionSession, settings: AppSettings) {
        self.settings = settings
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = settings.clickThrough
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: SubtitleView(session: session, settings: settings))
        session.$isCaptionVisible.combineLatest(session.$state, settings.$previewOverlay)
            .sink { [weak self] visible, state, preview in
                guard let self else { return }
                if visible || (preview && state != .running && state != .starting) { self.reposition(); self.panel.orderFrontRegardless() }
                else { self.panel.orderOut(nil) }
            }.store(in: &subscriptions)
        settings.$clickThrough.sink { [weak self] value in
            self?.panel.ignoresMouseEvents = value
        }.store(in: &subscriptions)
        settings.$position.sink { [weak self] position in
            self?.reposition(position: position)
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }.store(in: &subscriptions)
    }

    private func reposition(position: SubtitlePosition? = nil) {
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let width = min(960, visible.width - 64)
        let height = min(360, visible.height - 64)
        let y: CGFloat
        switch position ?? settings.position {
        case .top: y = visible.maxY - height - 32
        case .middle: y = visible.midY - height / 2
        case .bottom: y = visible.minY + 36
        }
        panel.setFrame(NSRect(x: visible.midX - width / 2, y: y, width: width, height: height), display: true)
    }
}
