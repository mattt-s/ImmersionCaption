import Foundation
import CoreAudio

enum AudioCaptureError: LocalizedError {
    case hardware(operation: String, status: OSStatus)
    case invalidFormat
    case formatChanged

    var errorDescription: String? {
        switch self {
        case let .hardware(operation, status):
            return "System audio capture could not \(operation) (Core Audio \(status)). Allow ImmersionCaption under System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, then restart captions. Screen recording and microphone access are not needed."
        case .invalidFormat:
            return "System audio returned an unsupported or invalid PCM format. Stop and restart captions after checking your audio output device."
        case .formatChanged:
            return "The system audio format changed. Restart captions to use the new audio output format."
        }
    }
}

/// Checks native status codes without logging audio or recognition content.
func checkAudioStatus(_ status: OSStatus, operation: String) throws {
    guard status == noErr else { throw AudioCaptureError.hardware(operation: operation, status: status) }
}
