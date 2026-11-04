import AppKit
import SwiftUI
import Combine
import ColorSync
import CaptionCore

/// Owns the caption panel and a small interactive child control. The child keeps
/// locking available even when the entire caption surface passes mouse events through.
@MainActor
final class SubtitleOverlayController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let lockPanel: NSPanel
    private let settings: AppSettings
    private var subscriptions = Set<AnyCancellable>()
    private var placement: OverlayPlacementPreference
    private var maximumCaptionLines: CaptionLineLimit
    private var fontSize: Double
    private var locked: Bool
    private var clickThrough: Bool
    private var captionVisible = false
    private var preview = false
    private var state: SessionState = .stopped
    private var applyingFrame = false
    private var recordingMove = false

    init(session: CaptionSession, settings: AppSettings) {
        self.settings = settings
        placement = settings.placement
        maximumCaptionLines = settings.maximumCaptionLines
        fontSize = settings.fontSize
        locked = settings.isOverlayLocked
        clickThrough = settings.clickThrough
        panel = Self.makePanel(identifier: "ImmersionCaption.captionOverlay")
        lockPanel = Self.makePanel(identifier: "ImmersionCaption.overlayLock")
        super.init()
        panel.delegate = self
        panel.isMovableByWindowBackground = false
        lockPanel.isMovable = false
        lockPanel.ignoresMouseEvents = false
        panel.contentView = NSHostingView(rootView: SubtitleView(session: session, settings: settings))
        lockPanel.contentView = LockControlHostingView(rootView: OverlayLockButton(settings: settings))
        panel.addChildWindow(lockPanel, ordered: .above)

        // Consume published values directly: @Published emits before its property changes.
        settings.$placement.combineLatest(settings.$fontSize, settings.$isOverlayLocked, settings.$clickThrough)
            .combineLatest(settings.$maximumCaptionLines)
            .sink { [weak self] appearance, lines in
                let (placement, size, locked, clickThrough) = appearance
                guard let self else { return }
                self.placement = placement
                self.maximumCaptionLines = lines
                self.fontSize = size
                self.locked = locked
                self.clickThrough = clickThrough
                self.panel.isMovable = !locked
                self.panel.ignoresMouseEvents = locked && clickThrough
                if !self.recordingMove { self.applyPlacement() }
                self.updateVisibility()
            }.store(in: &subscriptions)
        session.$isCaptionVisible.combineLatest(session.$state, settings.$previewOverlay)
            .sink { [weak self] visible, state, preview in
                guard let self else { return }
                self.captionVisible = visible
                self.state = state
                self.preview = preview
                self.updateVisibility()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.applyPlacement() }.store(in: &subscriptions)
        // performDrag hands tracking to WindowServer; a mouse-up is not guaranteed.
        // Coalesce movement to constrain an offscreen drop without depending on mouse-up.
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.constrainAfterMove() }.store(in: &subscriptions)
    }

    private static func makePanel(identifier: String) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier(identifier)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func updateVisibility() {
        let show = !locked || captionVisible || (preview && state != .running && state != .starting)
        if show {
            // Recognition updates must never reapply a preset while a window is being dragged.
            if !panel.isVisible { applyPlacement(); panel.orderFrontRegardless() }
            // orderOut detaches child windows; restore the relationship after every hide.
            if lockPanel.parent !== panel {
                positionLockControl()
                panel.addChildWindow(lockPanel, ordered: .above)
            }
            if !lockPanel.isVisible { lockPanel.orderFrontRegardless() }
        } else {
            lockPanel.orderOut(nil)
            panel.orderOut(nil)
        }
    }

    private var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        if let custom = placement.custom,
           let saved = screens.first(where: { Self.screenIdentifier($0) == custom.screenIdentifier }) {
            return saved
        }
        return screens.first
    }

    private func applyPlacement() {
        guard !recordingMove, let screen = targetScreen else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: min(960, max(1, visible.width - 64)),
                          height: min(max(1, visible.height - 32), CaptionTextMetrics(fontSize: fontSize).viewportHeight(for: maximumCaptionLines) +
                                      (locked && clickThrough ? 0 : 32) + 48))
        let bounds = visible.insetBy(dx: 8, dy: 8)
        let frame: CGRect?
        if let custom = placement.custom {
            frame = OverlayGeometry.restore(custom, size: size, visibleFrame: bounds)
        } else {
            let y: CGFloat
            switch placement.preset {
            case .top: y = visible.maxY - size.height - 32
            case .middle: y = visible.midY - size.height / 2
            case .bottom: y = visible.minY + 36
            }
            frame = OverlayGeometry.clamped(CGRect(x: visible.midX - size.width / 2, y: y,
                                                   width: size.width, height: size.height), to: bounds)
        }
        guard let frame else { return }
        applyingFrame = true
        panel.setFrame(frame, display: panel.isVisible)
        positionLockControl()
        applyingFrame = false
    }

    private func positionLockControl() {
        // The control is inside the caption's frame, in reserved trailing space.
        lockPanel.setFrame(NSRect(x: panel.frame.maxX - 44, y: panel.frame.maxY - 44,
                                  width: 28, height: 28), display: lockPanel.isVisible)
    }

    func windowDidMove(_ notification: Notification) {
        guard !locked, !applyingFrame, let screen = screenContaining(panel.frame),
              let saved = OverlayGeometry.save(frame: panel.frame,
                  visibleFrame: screen.visibleFrame.insetBy(dx: 8, dy: 8),
                  screenIdentifier: Self.screenIdentifier(screen)) else { return }
        // Saving is distinct from applying geometry: avoid a recursive snap during native dragging.
        recordingMove = true
        settings.saveCustomPosition(saved)
        recordingMove = false
    }

    private func constrainAfterMove() {
        guard !locked, !applyingFrame, let screen = targetScreen, let custom = placement.custom,
              let frame = OverlayGeometry.restore(custom, size: panel.frame.size,
                  visibleFrame: screen.visibleFrame.insetBy(dx: 8, dy: 8)) else { return }
        if abs(frame.minX - panel.frame.minX) > 0.5 || abs(frame.minY - panel.frame.minY) > 0.5 {
            applyPlacement()
        }
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        let handle = CGPoint(x: frame.midX, y: frame.maxY - 16)
        if let screen = screens.first(where: { $0.visibleFrame.contains(handle) }) { return screen }
        return screens.max {
            Self.intersectionArea(frame, $0.visibleFrame) < Self.intersectionArea(frame, $1.visibleFrame)
        }
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let overlap = lhs.intersection(rhs)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }

    private static func screenIdentifier(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
                return CFUUIDCreateString(nil, uuid) as String
            }
            return number.stringValue
        }
        return screen.localizedName
    }
}

/// Allows the lock control to work on the first click without activating another app's window.
private final class LockControlHostingView: NSHostingView<OverlayLockButton> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
