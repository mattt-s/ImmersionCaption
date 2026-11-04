import AppKit
import SwiftUI

/// Native wrapping/scrolling keeps a whole-line viewport without truncating the source text.
struct CaptionTextView: NSViewRepresentable {
    let text: String
    let fontSize: Double
    let followsLive: Bool
    let showsScrollIndicator: Bool

    func makeNSView(context: Context) -> CaptionScrollView { CaptionScrollView() }

    func updateNSView(_ view: CaptionScrollView, context: Context) {
        view.update(text: text, fontSize: fontSize, followsLive: followsLive,
                    showsScrollIndicator: showsScrollIndicator)
    }
}

/// TextKit uses equal paragraph line heights; the enclosing SwiftUI view supplies N lines of height.
/// The full three-request display buffer remains in the document for manual review.
final class CaptionScrollView: NSScrollView {
    let captionTextView = NSTextView(frame: .zero)
    private var followsLive = true
    private var currentFontSize: Double?
    private var updatingLayout = false

    init() {
        super.init(frame: .zero)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = false
        scrollerStyle = .overlay
        autohidesScrollers = true
        automaticallyAdjustsContentInsets = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        captionTextView.isEditable = false
        captionTextView.isSelectable = false
        captionTextView.drawsBackground = false
        captionTextView.textColor = .white
        captionTextView.textContainerInset = .zero
        captionTextView.isHorizontallyResizable = false
        captionTextView.isVerticallyResizable = true
        captionTextView.minSize = .zero
        captionTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        captionTextView.autoresizingMask = [.width]
        captionTextView.textContainer?.widthTracksTextView = true
        captionTextView.textContainer?.heightTracksTextView = false
        captionTextView.textContainer?.lineFragmentPadding = 0
        documentView = captionTextView
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    func update(text: String, fontSize: Double, followsLive: Bool, showsScrollIndicator: Bool) {
        self.followsLive = followsLive
        if hasVerticalScroller != showsScrollIndicator { hasVerticalScroller = showsScrollIndicator }
        if captionTextView.string != text || currentFontSize != fontSize {
            let metrics = CaptionTextMetrics(fontSize: fontSize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = metrics.lineHeight
            paragraph.maximumLineHeight = metrics.lineHeight
            paragraph.lineBreakMode = .byWordWrapping
            captionTextView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: metrics.font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph
            ]))
            currentFontSize = fontSize
        }
        layoutSubtreeIfNeeded()
        layoutDocument()
    }

    override func layout() {
        super.layout()
        layoutDocument()
    }

    private func layoutDocument() {
        guard !updatingLayout, contentSize.width > 0,
              let container = captionTextView.textContainer,
              let manager = captionTextView.layoutManager else { return }
        updatingLayout = true
        defer { updatingLayout = false }
        let previousOrigin = contentView.bounds.origin
        let width = contentSize.width
        if captionTextView.frame.width != width {
            captionTextView.setFrameSize(NSSize(width: width, height: captionTextView.frame.height))
        }
        manager.ensureLayout(for: container)
        let height = max(contentSize.height, ceil(manager.usedRect(for: container).maxY))
        let size = NSSize(width: width, height: height)
        if captionTextView.frame.size != size { captionTextView.setFrameSize(size) }
        let bottom = max(0, height - contentSize.height)
        contentView.scroll(to: NSPoint(x: 0, y: followsLive ? bottom : min(previousOrigin.y, bottom)))
        reflectScrolledClipView(contentView)
    }
}
