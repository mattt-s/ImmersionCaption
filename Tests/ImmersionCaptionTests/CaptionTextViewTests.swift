import XCTest
import AppKit
@testable import ImmersionCaption

@MainActor
final class CaptionTextViewTests: XCTestCase {
    func testOneTwoThreeWholeWrappedLinesAcrossFontsAndLanguages() throws {
        let samples = [
            String(repeating: "The newest words remain visible while earlier words stay in history. ", count: 12),
            String(repeating: "这是一段中文实时字幕，内容会自动换行并显示最新的文字。🙂", count: 12)
        ]
        for text in samples {
            for fontSize in [16.0, 28.0, 52.0] {
                for limit in CaptionLineLimit.allCases {
                    let view = makeView(fontSize: fontSize, limit: limit)
                    view.update(text: text, fontSize: fontSize, followsLive: true, showsScrollIndicator: false)
                    let (manager, container) = try textLayout(view)
                    let viewport = view.captionTextView.visibleRect
                    var visibleLines = 0
                    var totalLines = 0
                    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, _, _ in
                        totalLines += 1
                        if rect.intersection(viewport).height > 0.5 {
                            visibleLines += 1
                            XCTAssertEqual(rect.intersection(viewport).height, rect.height, accuracy: 0.5)
                        }
                    }
                    XCTAssertGreaterThan(totalLines, 3)
                    XCTAssertEqual(visibleLines, limit.rawValue, "Font \(fontSize), limit \(limit)")
                    XCTAssertEqual(view.captionTextView.string, text)
                    XCTAssertEqual(viewport.maxY, view.captionTextView.frame.height, accuracy: 0.5)
                }
            }
        }
    }

    func testFollowOffPreservesReviewAndReenablingShowsNewestText() {
        let view = makeView(fontSize: 28, limit: .two)
        let text = String(repeating: "Earlier caption text.\n", count: 30) + "Latest words."
        view.update(text: text, fontSize: 28, followsLive: true, showsScrollIndicator: true)
        XCTAssertGreaterThan(view.contentView.bounds.minY, 0)
        view.contentView.scroll(to: .zero)
        view.update(text: text + " New words.", fontSize: 28, followsLive: false, showsScrollIndicator: true)
        XCTAssertEqual(view.contentView.bounds.minY, 0, accuracy: 0.5)
        view.update(text: text + " New words.", fontSize: 28, followsLive: true, showsScrollIndicator: false)
        XCTAssertFalse(view.hasVerticalScroller)
        XCTAssertEqual(view.captionTextView.visibleRect.maxY, view.captionTextView.frame.height, accuracy: 0.5)
    }

    func testResizingAndLineLimitChangesKeepFollowingWithoutTruncatingText() {
        let view = makeView(fontSize: 28, limit: .three)
        let text = String(repeating: "A long caption that wraps naturally. ", count: 30)
        view.update(text: text, fontSize: 28, followsLive: true, showsScrollIndicator: false)
        let oldHeight = view.captionTextView.frame.height
        view.setFrameSize(NSSize(width: 220, height: CaptionTextMetrics(fontSize: 28).viewportHeight(for: .one)))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(view.captionTextView.frame.height, oldHeight)
        XCTAssertEqual(view.captionTextView.string, text)
        XCTAssertEqual(view.captionTextView.visibleRect.maxY, view.captionTextView.frame.height, accuracy: 0.5)
    }

    private func makeView(fontSize: Double, limit: CaptionLineLimit) -> CaptionScrollView {
        let view = CaptionScrollView()
        view.frame = NSRect(x: 0, y: 0, width: 380,
                            height: CaptionTextMetrics(fontSize: fontSize).viewportHeight(for: limit))
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func textLayout(_ view: CaptionScrollView) throws -> (NSLayoutManager, NSTextContainer) {
        let manager = try XCTUnwrap(view.captionTextView.layoutManager)
        let container = try XCTUnwrap(view.captionTextView.textContainer)
        manager.ensureLayout(for: container)
        return (manager, container)
    }
}
