import Foundation

enum SpeechError: LocalizedError {
    case permissionDenied, localModelUnavailable, finalizationTimedOut
    case finalizationBufferOverflow, invalidAudioTiming, unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Allow Speech Recognition for ImmersionCaption in System Settings → Privacy & Security. Microphone access is not needed."
        case .localModelUnavailable:
            return "On-device Mandarin recognition is unavailable. Enable/download Mandarin (China mainland) Dictation in System Settings → Keyboard, then retry. Availability depends on macOS and installed language assets. Cloud recognition is disabled."
        case .finalizationTimedOut:
            return "Speech recognition did not return a final result in time. Restart translation. Partial results were not translated."
        case .finalizationBufferOverflow:
            return "Speech recognition took too long to finalize and the audio buffer filled. Restart translation."
        case .invalidAudioTiming:
            return "System audio has invalid timing. Restart translation after checking your audio output device."
        case .unsupportedAudioFormat:
            return "The system audio format could not be measured safely. Try a different audio output device, then restart translation."
        }
    }
}
