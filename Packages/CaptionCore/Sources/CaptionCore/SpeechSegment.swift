import Foundation

/// Provider-neutral speech-unit timing; a provider may group several words into one unit.
/// The range uses UTF-16 offsets in the formatted transcript.
public struct SpeechSegment: Equatable {
    public let range: NSRange
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public var endTime: TimeInterval { startTime + duration }

    public init(range: NSRange, startTime: TimeInterval, duration: TimeInterval) {
        self.range = range
        self.startTime = startTime
        self.duration = duration
    }
}
