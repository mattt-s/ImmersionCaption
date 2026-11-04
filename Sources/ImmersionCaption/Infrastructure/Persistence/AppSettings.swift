import Foundation
import Combine
import CaptionCore

enum SubtitlePosition: String, CaseIterable, Identifiable, Codable {
    case top, middle, bottom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The maximum number of wrapped caption lines visible at once.
enum CaptionLineLimit: Int, CaseIterable, Identifiable {
    case one = 1, two, three
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .one: return "One"
        case .two: return "Two"
        case .three: return "Three"
        }
    }
}

/// A preset is retained as a fallback while a custom anchor is active.
struct OverlayPlacementPreference: Codable, Equatable {
    var preset: SubtitlePosition
    var custom: SavedOverlayPosition?
}

/// Stores preferences only. Audio and subtitle history are never persisted automatically.
@MainActor
final class AppSettings: ObservableObject {
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var maximumCaptionLines: CaptionLineLimit { didSet { defaults.set(maximumCaptionLines.rawValue, forKey: "maximumCaptionLines") } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    @Published private(set) var placement: OverlayPlacementPreference {
        didSet {
            if let data = try? JSONEncoder().encode(placement) { defaults.set(data, forKey: "overlayPlacement") }
            defaults.set(placement.preset.rawValue, forKey: "position")
        }
    }
    // Editing is transient: every app launch starts locked at the persisted position.
    @Published var isOverlayLocked = true
    @Published var languageIdentifier: String { didSet { defaults.set(languageIdentifier, forKey: "languageIdentifier") } }
    @Published var clickThrough: Bool { didSet { defaults.set(clickThrough, forKey: "clickThrough") } }
    @Published var previewOverlay = false
    let languages: [RecognitionLanguage]
    private let defaults: UserDefaults

    init(languages: [RecognitionLanguage], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let availableLanguages = languages.filter(\.supportsOnDeviceRecognition)
        self.languages = availableLanguages
        let stored = defaults.string(forKey: "languageIdentifier") ?? "zh-CN"
        languageIdentifier = RecognitionLanguage.matching(stored, in: availableLanguages)?.id
            ?? availableLanguages.first?.id ?? ""
        maximumCaptionLines = CaptionLineLimit(rawValue: defaults.integer(forKey: "maximumCaptionLines")) ?? .three
        clickThrough = defaults.object(forKey: "clickThrough") as? Bool ?? false
        // Retire settings from the removed backend and second subtitle line.
        ["endpoint", "model", "bilingual", "keepOnscreen"].forEach { defaults.removeObject(forKey: $0) }
        let storedSize = defaults.object(forKey: "fontSize") as? Double ?? 28
        let storedOpacity = defaults.object(forKey: "opacity") as? Double ?? 0.78
        fontSize = storedSize.isFinite ? min(52, max(16, storedSize)) : 28
        opacity = storedOpacity.isFinite ? min(1, max(0.2, storedOpacity)) : 0.78
        let preset = SubtitlePosition(rawValue: defaults.string(forKey: "position") ?? "") ?? .bottom
        if let data = defaults.data(forKey: "overlayPlacement"),
           let saved = try? JSONDecoder().decode(OverlayPlacementPreference.self, from: data),
           saved.custom?.isValid != false {
            placement = saved
        } else {
            placement = OverlayPlacementPreference(preset: preset, custom: nil)
        }
    }

    /// Unlocking temporarily permits interaction without changing the saved preference.
    var overlayIsClickThrough: Bool { isOverlayLocked && clickThrough }
    var positionIdentifier: String { placement.custom == nil ? placement.preset.rawValue : "custom" }

    func selectPositionPreset(_ preset: SubtitlePosition) {
        placement = OverlayPlacementPreference(preset: preset, custom: nil)
    }

    func saveCustomPosition(_ position: SavedOverlayPosition) {
        guard position.isValid else { return }
        let updated = OverlayPlacementPreference(preset: placement.preset, custom: position)
        if placement != updated { placement = updated }
    }

}
