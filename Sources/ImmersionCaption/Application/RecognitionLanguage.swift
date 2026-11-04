import Foundation

/// A locale reported by the recognizer and its current on-device capability.
struct RecognitionLanguage: Identifiable, Equatable {
    let id: String
    let name: String
    let supportsOnDeviceRecognition: Bool

    /// Matches saved locale identifiers across Apple's hyphen/underscore spellings.
    static func matching(_ identifier: String, in languages: [RecognitionLanguage]) -> RecognitionLanguage? {
        let key = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return languages.first { $0.id.replacingOccurrences(of: "_", with: "-").lowercased() == key }
    }
}
