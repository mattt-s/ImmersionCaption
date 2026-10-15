import Foundation

// Runs the actual production domain sources without requiring XCTest or SwiftPM.
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    guard value() else { fatalError("FAIL: \(description)") }
    checks += 1
}

var segmenter = TranscriptSegmenter(maximumCharacters: 8)
check(segmenter.ingest("别着急。慢慢来", isFinal: false) == ["别着急。"], "sentence boundary")
check(segmenter.ingest("别着急。慢慢来", isFinal: false).isEmpty, "no duplicate partial")
check(segmenter.flush() == ["慢慢来"], "stable tail")
check(segmenter.flush().isEmpty, "flush is idempotent")
segmenter.reset()
_ = segmenter.ingest("我们去北京", isFinal: false)
_ = segmenter.ingest("我们去南京", isFinal: false)
check(segmenter.flush() == ["我们去南京"], "draft correction")
segmenter.reset()
check(segmenter.ingest(String(repeating: "好", count: 18), isFinal: true).map { $0.count } == [8, 8, 2], "bounded source phrases")
segmenter.reset()
check(segmenter.ingest("？！你好！", isFinal: true) == ["你好！"], "ignore empty punctuation")
var queue = BoundedQueue<Int>(capacity: 2)
[1, 2, 3].forEach { queue.append($0) }
check(queue.droppedCount == 1, "overload accounting")
check(queue.popFirst() == 2 && queue.popFirst() == 3 && queue.popFirst() == nil, "FIFO after dropping oldest")
queue.removeAll()
check(queue.droppedCount == 0 && queue.count == 0, "queue reset")
for address in ["http://127.0.0.1:11434", "http://localhost:11434/", "http://[::1]:11434"] {
    check((try? LocalEndpoint.validate(address)) != nil, "accept loopback \(address)")
}
for address in ["http://example.com", "http://192.168.1.2", "http://localhost.example.com", "http://user@localhost", "http://localhost/proxy", "http://localhost?remote=1", "http://localhost#x"] {
    check((try? LocalEndpoint.validate(address)) == nil, "reject remote or ambiguous endpoint")
}
let context = (1...4).map { Caption(source: "源\($0)", translation: "English \($0)") }
let prompt = TranslationPrompt.make(for: TranslationInput(source: "别着急", context: context))
check(prompt.hasSuffix("\n\n\n别着急"), "TranslateGemma separator")
check(prompt.contains("English 4") && !prompt.contains("English 2"), "bounded context")
check(prompt.contains("natural, idiomatic") && prompt.contains("Do not add facts"), "translation quality policy")
check(SessionState.paused.canStart && !SessionState.running.canStart, "session start policy")
print("Passed \(checks) production domain checks.")
