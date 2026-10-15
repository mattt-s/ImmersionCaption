import AppKit
import AVFoundation
import Speech

/// Explicit developer check using a generated file, never system or microphone audio.
/// Runs inside the signed app so the test uses the app's existing Speech authorization.
@MainActor
final class SpeechSmokeCheck {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("--check-speech") }

    private let speech = AppleSpeechRecognizer()
    private var finalIDs: Set<UUID> = []
    private var firstFinalTime: TimeInterval?
    private var failure: String?

    /// Arguments: --check-speech <generated-audio-file> <metadata-report.json>.
    /// The report deliberately contains no audio, transcriptions, or translations.
    func run() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--check-speech"), arguments.count == flag + 3 else { return }
        let reportURL = URL(fileURLWithPath: arguments[flag + 2])
        let began = ProcessInfo.processInfo.systemUptime
        var report: [String: Any] = ["passed": false, "finalCount": 0]
        defer {
            speech.stop()
            report["elapsedSeconds"] = ProcessInfo.processInfo.systemUptime - began
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                try? data.write(to: reportURL, options: .atomic)
            }
        }
        // Do not create a permission dialog as a side effect of running diagnostics.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            report["failure"] = "Speech permission is not already granted to this app."
            return
        }
        do {
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: arguments[flag + 1]))
            let format = file.processingFormat
            let frames = AVAudioFrameCount(format.sampleRate * 0.02)
            let pcm = try required(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            let quiet = try required(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
            quiet.frameLength = frames
            for buffer in UnsafeMutableAudioBufferListPointer(quiet.mutableAudioBufferList) {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            let converter = try PCMBufferConverter(format: format.streamDescription.pointee)
            try await speech.start(onTranscript: { [weak self] event in
                guard let self, event.isFinal, !event.text.isEmpty else { return }
                self.finalIDs.insert(event.utteranceID)
                if self.firstFinalTime == nil { self.firstFinalTime = ProcessInfo.processInfo.systemUptime }
            }, onFailure: { [weak self] error in
                let native = error as NSError
                self?.failure = "\(native.domain) (\(native.code))"
            })
            let receive = speech.audioReceiver
            // Playback continues across a pause and through a second utterance. Both
            // must finalize before the 45-second maintenance rotation could help.
            for _ in 0..<2 {
                file.framePosition = 0
                while file.framePosition < file.length {
                    try await send(pcm, reading: file, converter: converter, receive: receive)
                }
                for _ in 0..<75 {
                    try await send(quiet, reading: nil, converter: converter, receive: receive)
                }
            }
            let feedingEnded = ProcessInfo.processInfo.systemUptime
            while finalIDs.count < 2, failure == nil,
                  ProcessInfo.processInfo.systemUptime - feedingEnded < 10 {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let finalizedDuringFeed = firstFinalTime.map { $0 < feedingEnded } ?? false
            report["finalCount"] = finalIDs.count
            report["pauseFinalizationCount"] = speech.pauseFinalizationCount
            report["finalizedDuringFeed"] = finalizedDuringFeed
            report["firstFinalSeconds"] = firstFinalTime.map { $0 - began }
            report["passed"] = finalIDs.count >= 2 && speech.pauseFinalizationCount >= 2 &&
                finalizedDuringFeed && failure == nil &&
                ProcessInfo.processInfo.systemUptime - began < 40
            if let failure { report["failure"] = failure }
        } catch {
            let native = error as NSError
            report["failure"] = "\(native.domain) (\(native.code))"
        }
    }

    private func send(_ pcm: AVAudioPCMBuffer, reading file: AVAudioFile?,
                      converter: PCMBufferConverter, receive: (CMSampleBuffer) -> Void) async throws {
        if let failure { throw NSError(domain: failure, code: 1) }
        if let file { try file.read(into: pcm) }
        if let sample = try converter.convert(pcm.audioBufferList) { receive(sample) }
        let duration = Double(pcm.frameLength) / pcm.format.sampleRate
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }

    private func required<T>(_ value: T?) throws -> T {
        guard let value else { throw SpeechError.unsupportedAudioFormat }
        return value
    }
}
