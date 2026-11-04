import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import CaptionCore

final class OverlayGeometryTests: XCTestCase {
    func testRoundTripOnDisplayWithNegativeOrigin() throws {
        let screen = CGRect(x: -1920, y: 40, width: 1920, height: 1040)
        let frame = CGRect(x: -1700, y: 500, width: 960, height: 220)
        let saved = try XCTUnwrap(OverlayGeometry.save(frame: frame, visibleFrame: screen, screenIdentifier: "external"))
        XCTAssertEqual(saved.screenIdentifier, "external")
        XCTAssertEqual(OverlayGeometry.restore(saved, size: frame.size, visibleFrame: screen), frame)
    }

    func testControlAndFontHeightChangesPreserveTopLeftAnchor() throws {
        let screen = CGRect(x: 0, y: 30, width: 1500, height: 900)
        let original = CGRect(x: 100, y: 400, width: 960, height: 220)
        let saved = try XCTUnwrap(OverlayGeometry.save(frame: original, visibleFrame: screen, screenIdentifier: "main"))
        let restored = try XCTUnwrap(OverlayGeometry.restore(saved, size: CGSize(width: 960, height: 300), visibleFrame: screen))
        XCTAssertEqual(restored.minX, original.minX, accuracy: 0.001)
        XCTAssertEqual(restored.maxY, original.maxY, accuracy: 0.001)
    }

    func testMissingMonitorOrSmallerResolutionKeepsEntireWindowReachable() throws {
        let saved = SavedOverlayPosition(screenIdentifier: "disconnected", horizontalFraction: 0.8, verticalFraction: 0.8)
        let fallback = CGRect(x: 0, y: 30, width: 1000, height: 700)
        let frame = try XCTUnwrap(OverlayGeometry.restore(saved, size: CGSize(width: 960, height: 280), visibleFrame: fallback))
        XCTAssertTrue(fallback.contains(frame))
        XCTAssertEqual(frame.maxX, fallback.maxX)
        XCTAssertEqual(frame.minY, fallback.minY)
    }

    func testOffscreenOrOversizedFramesAreClampedBeforeSaving() throws {
        let bounds = CGRect(x: 10, y: 20, width: 800, height: 600)
        XCTAssertEqual(OverlayGeometry.clamped(CGRect(x: -1000, y: 900, width: 1200, height: 900), to: bounds), bounds)
        let saved = try XCTUnwrap(OverlayGeometry.save(frame: CGRect(x: -400, y: -500, width: 400, height: 200), visibleFrame: bounds, screenIdentifier: "main"))
        let restored = try XCTUnwrap(OverlayGeometry.restore(saved, size: CGSize(width: 400, height: 200), visibleFrame: bounds))
        XCTAssertEqual(restored.minX, bounds.minX)
        XCTAssertEqual(restored.minY, bounds.minY, accuracy: 0.001)
    }

    func testInvalidPersistedAnchorsAndGeometryAreRejected() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 960, height: 220)
        for saved in [
            SavedOverlayPosition(screenIdentifier: "", horizontalFraction: 0, verticalFraction: 0),
            SavedOverlayPosition(screenIdentifier: "main", horizontalFraction: .nan, verticalFraction: 0),
            SavedOverlayPosition(screenIdentifier: "main", horizontalFraction: 0, verticalFraction: .infinity),
            SavedOverlayPosition(screenIdentifier: "main", horizontalFraction: -0.1, verticalFraction: 0),
            SavedOverlayPosition(screenIdentifier: "main", horizontalFraction: 0, verticalFraction: 1.1)
        ] {
            XCTAssertNil(OverlayGeometry.restore(saved, size: size, visibleFrame: bounds))
        }
        XCTAssertNil(OverlayGeometry.clamped(.zero, to: bounds))
        XCTAssertNil(OverlayGeometry.clamped(bounds, to: .zero))
        let valid = SavedOverlayPosition(screenIdentifier: "main", horizontalFraction: 0, verticalFraction: 0)
        XCTAssertNil(OverlayGeometry.restore(valid, size: CGSize(width: CGFloat.infinity, height: 20), visibleFrame: bounds))
    }
}
