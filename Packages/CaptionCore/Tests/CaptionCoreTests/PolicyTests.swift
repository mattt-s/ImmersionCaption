import XCTest
@testable import CaptionCore

final class PolicyTests: XCTestCase {
    func testCaptionRoundTripPreservesRecognizedTextAndIdentity() throws {
        let caption = Caption(text: "今天先这样。", createdAt: Date(timeIntervalSince1970: 100))
        let encoded = try JSONEncoder().encode(caption)
        let restored = try JSONDecoder().decode(Caption.self, from: encoded)
        XCTAssertEqual(restored, caption)
        XCTAssertEqual(restored.text, "今天先这样。")
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(keys.keys), ["id", "text", "createdAt"])
    }

    func testLifecycleStartPolicy() {
        XCTAssertTrue(SessionState.stopped.canStart)
        XCTAssertTrue(SessionState.failed.canStart)
        XCTAssertTrue(SessionState.paused.canStart)
        XCTAssertFalse(SessionState.starting.canStart)
        XCTAssertFalse(SessionState.running.canStart)
    }
}
