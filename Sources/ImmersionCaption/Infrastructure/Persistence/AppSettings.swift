import Foundation
import Combine
import CaptionCore

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
    @Published var bilingual: Bool { didSet { defaults.set(bilingual, forKey: "bilingual") } }
    @Published var captionLength: CaptionLength { didSet { defaults.set(captionLength.rawValue, forKey: "captionLength") } }
    @Published var endpoint: String { didSet { defaults.set(endpoint, forKey: "endpoint") } }
    @Published var model: String { didSet { defaults.set(model, forKey: "model") } }
    @Published var previewOverlay = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedSize = defaults.object(forKey: "fontSize") as? Double ?? 28
        let storedOpacity = defaults.object(forKey: "opacity") as? Double ?? 0.78
        fontSize = storedSize.isFinite ? min(52, max(16, storedSize)) : 28
        opacity = storedOpacity.isFinite ? min(1, max(0.2, storedOpacity)) : 0.78
        position = SubtitlePosition(rawValue: defaults.string(forKey: "position") ?? "") ?? .bottom
        bilingual = defaults.bool(forKey: "bilingual")
        captionLength = CaptionLength(rawValue: defaults.string(forKey: "captionLength") ?? "") ?? .short
        endpoint = defaults.string(forKey: "endpoint") ?? "http://127.0.0.1:11434"
        model = defaults.string(forKey: "model") ?? "translategemma:4b"
    }
}
