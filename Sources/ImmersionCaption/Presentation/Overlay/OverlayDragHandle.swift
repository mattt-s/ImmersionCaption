import AppKit
import SwiftUI

/// A dedicated drag surface leaves caption scrolling and other buttons independent.
struct OverlayDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragSurface { DragSurface() }
    func updateNSView(_ nsView: DragSurface, context: Context) { }

    final class DragSurface: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            guard let window, window.isMovable else { return }
            window.performDrag(with: event)
        }
    }
}
