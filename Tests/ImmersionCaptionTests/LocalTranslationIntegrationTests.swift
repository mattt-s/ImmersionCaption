import XCTest
import CaptionCore
@testable import ImmersionCaption

/// Opt-in coverage for the production adapter against the user's installed local model.
@MainActor
final class LocalTranslationIntegrationTests: XCTestCase {
    func testInstalledTranslateGemmaReturnsEnglish() async throws {
        guard ProcessInfo.processInfo.environment["IMMERSIONCAPTION_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set IMMERSIONCAPTION_LIVE_TEST=1 with local Ollama running to test actual inference.")
        }
        let engine = OllamaTranslationEngine(
            endpoint: { "http://127.0.0.1:11434" },
            model: { "translategemma:4b" }
        )
        let result = try await engine.translate(TranslationInput(source: "别着急，咱们一步一步来。"))
        XCTAssertFalse(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(result.range(of: "[A-Za-z]", options: .regularExpression), "Expected English text.")
        XCTAssertLessThan(result.count, 500, "A short phrase should produce a short translation, not commentary.")
    }
}
