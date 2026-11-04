import Foundation

// Runs the actual production domain sources without requiring XCTest or SwiftPM.
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    guard value() else { fatalError("FAIL: \(description)") }
    checks += 1
}

var segmenter = TranscriptSegmenter()
check(segmenter.ingest("别着急。慢慢来", isFinal: false) == ["别着急。"], "sentence boundary")
check(segmenter.ingest("别着急。慢慢来", isFinal: false).isEmpty, "no duplicate partial")
check(segmenter.flush() == ["慢慢来"], "final tail")
check(segmenter.flush().isEmpty, "flush is idempotent")
segmenter.reset()
_ = segmenter.ingest("我们去北京", isFinal: false)
_ = segmenter.ingest("我们去南京", isFinal: false)
check(segmenter.flush() == ["我们去南京"], "draft correction")
segmenter.reset()
check(segmenter.ingest(String(repeating: "好", count: 18), isFinal: true).map { $0.count } == [18], "unpunctuated utterance remains intact")
segmenter.reset()
check(segmenter.ingest("？！你好！", isFinal: true) == ["你好！"], "ignore empty punctuation")
let caption = Caption(text: "你好。")
check(caption.text == "你好。", "recognized caption text")
let encoded = try JSONEncoder().encode(caption)
let decoded = try JSONDecoder().decode(Caption.self, from: encoded)
check(decoded == caption, "caption round trip")
check(SessionState.paused.canStart && !SessionState.running.canStart, "session start policy")
print("Passed \(checks) production domain checks.")
