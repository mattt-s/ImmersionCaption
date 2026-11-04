import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A display-relative top-left anchor, independent of the caption's current size.
/// Fractions let saved locations survive resolution changes and missing monitors.
public struct SavedOverlayPosition: Codable, Equatable {
    public let screenIdentifier: String
    public let horizontalFraction: Double
    public let verticalFraction: Double

    public init(screenIdentifier: String, horizontalFraction: Double, verticalFraction: Double) {
        self.screenIdentifier = screenIdentifier
        self.horizontalFraction = horizontalFraction
        self.verticalFraction = verticalFraction
    }

    public var isValid: Bool {
        !screenIdentifier.isEmpty && horizontalFraction.isFinite && verticalFraction.isFinite &&
            (0...1).contains(horizontalFraction) && (0...1).contains(verticalFraction)
    }
}

/// Pure geometry for persistence and reachable positioning; AppKit owns native dragging.
public enum OverlayGeometry {
    /// Fits the entire frame inside visible screen bounds, including oversized windows.
    public static func clamped(_ frame: CGRect, to visible: CGRect) -> CGRect? {
        guard valid(frame), valid(visible) else { return nil }
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                      y: min(max(frame.minY, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }

    public static func save(frame: CGRect, visibleFrame: CGRect, screenIdentifier: String) -> SavedOverlayPosition? {
        guard !screenIdentifier.isEmpty, let frame = clamped(frame, to: visibleFrame) else { return nil }
        return SavedOverlayPosition(screenIdentifier: screenIdentifier,
            horizontalFraction: Double((frame.minX - visibleFrame.minX) / visibleFrame.width),
            verticalFraction: Double((visibleFrame.maxY - frame.maxY) / visibleFrame.height))
    }

    /// Preserves the top-left anchor as controls/font size change, then clamps if needed.
    public static func restore(_ position: SavedOverlayPosition, size: CGSize, visibleFrame: CGRect) -> CGRect? {
        guard position.isValid, valid(visibleFrame), size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return nil }
        let frame = CGRect(x: visibleFrame.minX + CGFloat(position.horizontalFraction) * visibleFrame.width,
                           y: visibleFrame.maxY - CGFloat(position.verticalFraction) * visibleFrame.height - size.height,
                           width: size.width, height: size.height)
        return clamped(frame, to: visibleFrame)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.width.isFinite && frame.height.isFinite &&
            frame.width > 0 && frame.height > 0
    }
}
