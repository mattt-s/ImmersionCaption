import Foundation
import Combine

enum SubtitlePosition: String, CaseIterable, Identifiable {
    case top, middle, bottom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Stores preferences only. Audio and subtitle history are never persisted automatically.
@MainActor
final class AppSettings: ObservableObject {
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    @Published var position: SubtitlePosition { didSet { defaults.set(position.rawValue, forKey: "position") } }
    @Published var languageIdentifier: String { didSet { defaults.set(languageIdentifier, forKey: "languageIdentifier") } }
    @Published var clickThrough: Bool { didSet { defaults.set(clickThrough, forKey: "clickThrough") } }
    @Published var keepOnscreen: Bool { didSet { defaults.set(keepOnscreen, forKey: "keepOnscreen") } }
    @Published var previewOverlay = false
    let languages: [RecognitionLanguage]
    private let defaults: UserDefaults

    init(languages: [RecognitionLanguage], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.languages = languages
        let stored = defaults.string(forKey: "languageIdentifier") ?? "zh-CN"
        languageIdentifier = RecognitionLanguage.matching(stored, in: languages)?.id
            ?? languages.first(where: { $0.supportsOnDeviceRecognition })?.id
            ?? languages.first?.id ?? ""
        clickThrough = defaults.object(forKey: "clickThrough") as? Bool ?? false
        keepOnscreen = defaults.bool(forKey: "keepOnscreen")
        // Retire settings from the removed backend and second subtitle line.
        ["endpoint", "model", "bilingual"].forEach { defaults.removeObject(forKey: $0) }
        let storedSize = defaults.object(forKey: "fontSize") as? Double ?? 28
        let storedOpacity = defaults.object(forKey: "opacity") as? Double ?? 0.78
        fontSize = storedSize.isFinite ? min(52, max(16, storedSize)) : 28
        opacity = storedOpacity.isFinite ? min(1, max(0.2, storedOpacity)) : 0.78
        position = SubtitlePosition(rawValue: defaults.string(forKey: "position") ?? "") ?? .bottom
    }
}
