import XCTest
import AppKit
import CoreMedia
@testable import ImmersionCaption

/// Native window metadata tests; fixtures never request permission or capture audio.
@MainActor
final class SubtitleOverlayControllerTests: XCTestCase {
    func testUnlockShowsBothPanelsAndRelockRestoresClickThroughAndSilenceHiding() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let (settings, overlay) = (fixture.settings, fixture.overlay)
        XCTAssertFalse(overlay.panel.isVisible)
        settings.clickThrough = true
        settings.isOverlayLocked = false
        XCTAssertTrue(overlay.panel.isVisible)
        XCTAssertTrue(overlay.lockPanel.isVisible)
        XCTAssertTrue(overlay.panel.isMovable)
        XCTAssertFalse(overlay.panel.ignoresMouseEvents)
        XCTAssertFalse(overlay.lockPanel.ignoresMouseEvents)
        XCTAssertTrue(overlay.lockPanel.parent === overlay.panel)
        XCTAssertTrue(settings.clickThrough)

        settings.isOverlayLocked = true
        XCTAssertFalse(overlay.panel.isVisible)
        XCTAssertFalse(overlay.lockPanel.isVisible)
        XCTAssertFalse(overlay.panel.isMovable)
        XCTAssertTrue(overlay.panel.ignoresMouseEvents)
        settings.previewOverlay = true
        XCTAssertTrue(overlay.panel.isVisible)
        XCTAssertTrue(overlay.lockPanel.isVisible)
        XCTAssertTrue(overlay.lockPanel.parent === overlay.panel)
        settings.previewOverlay = false
        XCTAssertFalse(overlay.panel.isVisible)
        settings.isOverlayLocked = false
        XCTAssertTrue(overlay.lockPanel.parent === overlay.panel)
        let offset = overlay.lockPanel.frame.minX - overlay.panel.frame.minX
        overlay.panel.setFrameOrigin(overlay.panel.frame.origin.applying(CGAffineTransform(translationX: 10, y: 0)))
        XCTAssertEqual(overlay.lockPanel.frame.minX - overlay.panel.frame.minX, offset, accuracy: 0.5)
    }

    func testMovingSavesLocationAndSpeechVisibilityUpdatesDoNotSnapItBack() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let (settings, overlay) = (fixture.settings, fixture.overlay)
        settings.clickThrough = true
        settings.isOverlayLocked = false
        let bounds = try XCTUnwrap(NSScreen.screens.first).visibleFrame
        overlay.panel.setFrameOrigin(CGPoint(x: bounds.minX + 40, y: bounds.maxY - overlay.panel.frame.height - 80))
        // WindowServer notifications may be deferred during a programmatic test move.
        overlay.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: overlay.panel))
        XCTAssertNotNil(settings.placement.custom)
        let moved = overlay.panel.frame
        await fixture.session.start()
        fixture.speech.emit("Caption one")
        fixture.speech.emit("Caption one revised")
        XCTAssertEqual(overlay.panel.frame, moved)

        settings.isOverlayLocked = true
        XCTAssertEqual(overlay.panel.frame.minX, moved.minX, accuracy: 0.5)
        XCTAssertEqual(overlay.panel.frame.maxY, moved.maxY, accuracy: 0.5)
        XCTAssertTrue(overlay.lockPanel.isVisible)
        XCTAssertTrue(overlay.panel.ignoresMouseEvents)
        await fixture.session.stop()
        XCTAssertFalse(overlay.panel.isVisible)
        settings.previewOverlay = true
        XCTAssertEqual(overlay.panel.frame.minX, moved.minX, accuracy: 0.5)
        XCTAssertEqual(overlay.panel.frame.maxY, moved.maxY, accuracy: 0.5)
        settings.fontSize = 36
        XCTAssertEqual(overlay.panel.frame.maxY, moved.maxY, accuracy: 0.5)
        settings.selectPositionPreset(.top)
        XCTAssertNil(settings.placement.custom)
        XCTAssertEqual(overlay.panel.frame.maxY, bounds.maxY - 32, accuracy: 0.5)
    }

    private func makeFixture() throws -> OverlayFixture {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Native overlay checks require a window server") }
        let suite = "ImmersionCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = AppSettings(languages: [RecognitionLanguage(id: "en-US", name: "English", supportsOnDeviceRecognition: true)], defaults: defaults)
        let speech = OverlaySpeechFixture()
        let session = CaptionSession(capture: OverlayCaptureFixture(), speech: speech,
            makeActivityMonitor: { OverlayActivityFixture() }, selectedLanguage: { "en-US" }, now: { 100 })
        let overlay = SubtitleOverlayController(session: session, settings: settings)
        // Inspect real panel metadata without drawing test overlays over the user's work.
        overlay.panel.alphaValue = 0
        overlay.lockPanel.alphaValue = 0
        return OverlayFixture(settings: settings, overlay: overlay, session: session, speech: speech,
                              defaults: defaults, suite: suite)
    }
}

@MainActor
private struct OverlayFixture {
    let settings: AppSettings
    let overlay: SubtitleOverlayController
    let session: CaptionSession
    let speech: OverlaySpeechFixture
    let defaults: UserDefaults
    let suite: String
    func cleanUp() {
        overlay.panel.removeChildWindow(overlay.lockPanel)
        overlay.lockPanel.close()
        overlay.panel.close()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class OverlayCaptureFixture: SystemAudioCapturing {
    func start(receive: @escaping (CMSampleBuffer) -> Void, onFailure: @escaping @MainActor (Error) -> Void) async throws {}
    func stop() async {}
}

@MainActor
private final class OverlaySpeechFixture: SpeechRecognizing {
    private var callback: (@MainActor (TranscriptEvent) -> Void)?
    private let id = UUID()
    var audioReceiver: (CMSampleBuffer) -> Void { { _ in } }
    func start(languageIdentifier: String, onTranscript: @escaping @MainActor (TranscriptEvent) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws { callback = onTranscript }
    func stop() { callback = nil }
    func emit(_ text: String) { callback?(TranscriptEvent(utteranceID: id, text: text, isFinal: false)) }
}

private final class OverlayActivityFixture: AudioActivityMonitoring, @unchecked Sendable {
    var lastAudibleTime: TimeInterval? { 100 }
    func consume(_ sample: CMSampleBuffer) {}
}
