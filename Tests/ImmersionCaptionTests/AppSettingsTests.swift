import XCTest
@testable import ImmersionCaption

@MainActor
final class AppSettingsTests: XCTestCase {
    private let languages = [
        RecognitionLanguage(id: "en-US", name: "English (US)", supportsOnDeviceRecognition: true),
        RecognitionLanguage(id: "zh-CN", name: "Chinese", supportsOnDeviceRecognition: true),
        RecognitionLanguage(id: "ja-JP", name: "Japanese", supportsOnDeviceRecognition: false)
    ]

    func testLanguageAndAppearancePersistWhileRetiredSettingsAreRemoved() throws {
        let suite = "ImmersionCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("old", forKey: "model")
        defaults.set(true, forKey: "bilingual")
        defaults.set(true, forKey: "keepOnscreen")
        defaults.set(36.0, forKey: "fontSize")
        defaults.set("en_US", forKey: "languageIdentifier")
        let settings = AppSettings(languages: languages, defaults: defaults)
        XCTAssertEqual(settings.languages.map(\.id), ["en-US", "zh-CN"])
        XCTAssertEqual(settings.languageIdentifier, "en-US")
        XCTAssertEqual(settings.fontSize, 36)
        XCTAssertNil(defaults.object(forKey: "model"))
        XCTAssertNil(defaults.object(forKey: "bilingual"))
        XCTAssertNil(defaults.object(forKey: "keepOnscreen"))
        XCTAssertFalse(settings.clickThrough)
        settings.clickThrough = true
        settings.languageIdentifier = "zh-CN"
        let restored = AppSettings(languages: languages, defaults: defaults)
        XCTAssertEqual(restored.languageIdentifier, "zh-CN")
        XCTAssertTrue(restored.clickThrough)
    }

    func testMissingSavedLocaleFallsBackToAnOnDeviceOption() throws {
        let suite = "ImmersionCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for saved in ["unsupported", "ja-JP"] {
            defaults.set(saved, forKey: "languageIdentifier")
            XCTAssertEqual(AppSettings(languages: languages, defaults: defaults).languageIdentifier, "en-US")
        }
    }

    func testEmptyCatalogIsRepresentedWithoutInventingLanguageSupport() throws {
        let suite = "ImmersionCaptionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for catalog in [[], [languages[2]]] {
            let settings = AppSettings(languages: catalog, defaults: defaults)
            XCTAssertTrue(settings.languages.isEmpty)
            XCTAssertEqual(settings.languageIdentifier, "")
        }
    }
}
