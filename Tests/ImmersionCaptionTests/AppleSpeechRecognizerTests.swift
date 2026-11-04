import XCTest
@testable import ImmersionCaption

@MainActor
final class AppleSpeechRecognizerTests: XCTestCase {
    func testEmptyLanguageFailsBeforeRequestingPermissionOrStartingRecognition() async {
        let recognizer = AppleSpeechRecognizer()
        do {
            try await recognizer.start(languageIdentifier: "", onTranscript: { _ in
                XCTFail("No recognition may start without a selected language")
            }, onFailure: { _ in })
            XCTFail("Missing language must fail explicitly")
        } catch SpeechError.localModelUnavailable(let language) {
            XCTAssertEqual(language, "the selected language")
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}
