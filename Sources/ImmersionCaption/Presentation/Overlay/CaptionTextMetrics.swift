import AppKit

/// Shared sizing for the native text viewport and its containing overlay panel.
struct CaptionTextMetrics {
    let font: NSFont
    let lineHeight: CGFloat

    init(fontSize: Double) {
        font = .systemFont(ofSize: fontSize, weight: .medium)
        // Leave room for CJK/emoji fallback glyphs while keeping uniform line fragments.
        lineHeight = ceil(max(font.ascender - font.descender + font.leading, fontSize * 1.4))
    }

    func viewportHeight(for limit: CaptionLineLimit) -> CGFloat {
        lineHeight * CGFloat(limit.rawValue)
    }
}
