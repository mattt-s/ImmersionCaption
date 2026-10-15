import XCTest
@testable import CaptionCore

final class PolicyTests: XCTestCase {
    func testQueueDropsOldestPendingWorkAndKeepsOrder() {
        var queue = BoundedQueue<String>(capacity: 2)
        ["old", "next", "new"].forEach { queue.append($0) }
        XCTAssertEqual(queue.droppedCount, 1)
        XCTAssertEqual(queue.popFirst(), "next")
        XCTAssertEqual(queue.popFirst(), "new")
        XCTAssertNil(queue.popFirst())
        queue.removeAll()
        XCTAssertEqual(queue.droppedCount, 0)
    }

    func testPromptUsesChineseEnglishContractAndBoundedContext() {
        let context = (1...4).map { Caption(source: "源\($0)", translation: "English \($0)") }
        let input = TranslationInput(source: "别着急", context: context)
        let prompt = TranslationPrompt.make(for: input)
        XCTAssertTrue(prompt.contains("Chinese (zh-Hans) to English (en)"))
        XCTAssertTrue(prompt.contains("natural, idiomatic spoken English"))
        XCTAssertTrue(prompt.contains("Do not add facts"))
        XCTAssertTrue(prompt.hasSuffix("\n\n\n别着急"))
        XCTAssertTrue(prompt.contains("English 4"))
        XCTAssertFalse(prompt.contains("English 2"))
        XCTAssertEqual(input.context.count, 2)
    }

    func testOnlyExplicitLoopbackEndpointsAccepted() throws {
        for address in ["http://localhost:11434", "http://127.0.0.1:11434/", "http://[::1]:11434"] {
            XCTAssertNoThrow(try LocalEndpoint.validate(address), address)
        }
        for address in ["https://example.com", "http://192.168.1.2:11434", "http://localhost.example.com", "file:///tmp/model", "http://user@localhost", "http://127.0.0.1/api", "http://localhost?proxy=remote", "http://localhost#x"] {
            XCTAssertThrowsError(try LocalEndpoint.validate(address), address)
        }
    }

    func testLifecycleStartPolicy() {
        XCTAssertTrue(SessionState.stopped.canStart)
        XCTAssertTrue(SessionState.failed.canStart)
        XCTAssertTrue(SessionState.paused.canStart)
        XCTAssertFalse(SessionState.starting.canStart)
        XCTAssertFalse(SessionState.running.canStart)
    }
}
