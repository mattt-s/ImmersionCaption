import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    guard value() else { fatalError("FAIL: \(description)") }
    checks += 1
}
var transcript = LiveTranscript(capacity: 2)
let first = UUID()
check(transcript.update(requestID: first, text: "Hello", languageIdentifier: "en-US", isFinal: false), "immediate partial")
check(transcript.captions.first?.text == "Hello", "partial text")
check(transcript.update(requestID: first, text: "Hello again", languageIdentifier: "en-US", isFinal: false), "revision")
check(transcript.captions.count == 1, "replace instead of append")
check(!transcript.update(requestID: first, text: "Hello again", languageIdentifier: "en-US", isFinal: false), "duplicate update")
check(transcript.update(requestID: first, text: "Hello again", languageIdentifier: "en-US", isFinal: true), "final marks existing block")
check(!transcript.update(requestID: first, text: "Wrong", languageIdentifier: "en-US", isFinal: false), "final is immutable")
for _ in 0..<2 { transcript.update(requestID: UUID(), text: "Hello", languageIdentifier: "en-US", isFinal: true) }
check(transcript.captions.count == 2, "bounded history")
let caption = Caption(text: "こんにちは", languageIdentifier: "ja-JP")
let decoded = try JSONDecoder().decode(Caption.self, from: JSONEncoder().encode(caption))
check(decoded == caption, "caption round trip")
transcript.removeAll()
check(transcript.captions.isEmpty, "clear")
check(SessionState.paused.canStart && !SessionState.running.canStart, "lifecycle policy")
print("Passed \(checks) production domain checks.")
