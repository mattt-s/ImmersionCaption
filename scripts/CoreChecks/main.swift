import Foundation

// Runs the actual production domain sources without requiring XCTest or SwiftPM.
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    guard value() else { fatalError("FAIL: \(description)") }
    checks += 1
}

var gate = FinalTranscriptGate()
let requestID = UUID()
check(gate.consume(utteranceID: requestID, text: "黄埔岗，另一部分往北走。", isFinal: false) == nil, "punctuated drafts are preview only")
check(gate.consume(utteranceID: requestID, text: "黄埔港，另一部分往北走。", isFinal: true) == "黄埔港，另一部分往北走。", "only final text is translated")
check(gate.consume(utteranceID: requestID, text: "黄埔岗，", isFinal: true) == nil, "duplicate final rejected")
check(gate.consume(utteranceID: UUID(), text: "谢谢。", isFinal: true) == "谢谢。", "first spoken phrase")
check(gate.consume(utteranceID: UUID(), text: "谢谢。", isFinal: true) == "谢谢。", "genuine repeated phrase")
gate.reset()
check(gate.consume(utteranceID: requestID, text: "谢谢。", isFinal: true) == "谢谢。", "session reset")
check(gate.consume(utteranceID: UUID(), text: " \n ", isFinal: true) == nil, "empty final ignored")
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
