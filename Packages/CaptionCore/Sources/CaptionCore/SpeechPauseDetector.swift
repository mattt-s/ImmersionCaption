import Foundation

/// Detects sustained quiet in audio, not grammatical sentence boundaries or speech content.
/// Recognition must independently confirm speech before the caller ends a request.
public struct SpeechPauseDetector {
    public let quietDuration: TimeInterval
    private let activityThreshold: Double
    private let minimumActivityDuration: TimeInterval
    private var activeDuration: TimeInterval = 0
    private var quietTime: TimeInterval = 0

    /// - Parameters:
    ///   - quietDuration: Quiet audio required before requesting native finalization.
    ///   - activityThreshold: RMS amplitude in normalized PCM; -45 dBFS by default.
    ///   - minimumActivityDuration: Rejects short clicks and leading silence.
    public init(quietDuration: TimeInterval = 1,
                activityThreshold: Double = 0.005623413251903491,
                minimumActivityDuration: TimeInterval = 0.2) {
        self.quietDuration = quietDuration
        self.activityThreshold = activityThreshold
        self.minimumActivityDuration = minimumActivityDuration
    }

    public var hasActivity: Bool { activeDuration + 0.000_001 >= minimumActivityDuration }
    public var hasPause: Bool { hasActivity && quietTime + 0.000_001 >= quietDuration }

    /// Uses audio duration, so endpoint decisions do not depend on callback buffer size.
    public mutating func observe(rms: Double, duration: TimeInterval) {
        guard rms.isFinite, rms >= 0, duration.isFinite, duration > 0 else {
            quietTime = 0
            return
        }
        if rms >= activityThreshold {
            activeDuration = min(minimumActivityDuration, activeDuration + duration)
            quietTime = 0
        } else if hasActivity {
            quietTime = min(quietDuration, quietTime + duration)
        }
    }

    public mutating func reset() {
        activeDuration = 0
        quietTime = 0
    }
}
