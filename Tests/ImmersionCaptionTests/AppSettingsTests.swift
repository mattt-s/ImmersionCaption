import XCTest
@testable import ImmersionCaption

@MainActor
final class AppSettingsTests: XCTestCase {
    func testRetiredBackendSettingsAreRemovedAndAppearancePreserved() throws {
        let suite = "ImmersionCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("http://localhost:11434", forKey: "endpoint")
        defaults.set("old-model", forKey: "model")
        defaults.set(true, forKey: "bilingual")
        defaults.set(36.0, forKey: "fontSize")
        defaults.set(0.6, forKey: "opacity")
        defaults.set("top", forKey: "position")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.fontSize, 36)
        XCTAssertEqual(settings.opacity, 0.6)
        XCTAssertEqual(settings.position, .top)
        for key in ["endpoint", "model", "bilingual"] {
            XCTAssertNil(defaults.object(forKey: key))
        }
        settings.position = .middle
        XCTAssertEqual(defaults.string(forKey: "position"), "middle")
    }
}
