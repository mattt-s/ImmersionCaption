import Foundation
import ScreenCaptureKit
import CoreMedia

enum CaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? {
        "No display is available for system audio capture. Connect a display and try again."
    }
}

/// ScreenCaptureKit requires a display filter, but only audio output is registered and consumed.
@MainActor
final class ScreenAudioCapture: SystemAudioCapturing {
    private var stream: SCStream?
    private var output: AudioOutput?
    private var generation = UUID()
    private let queue = DispatchQueue(label: "app.ImmersionCaption.audio", qos: .userInitiated)

    func start(receive: @escaping (CMSampleBuffer) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws {
        await stop()
        let token = generation
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard let display = content.displays.first else { throw CaptureError.noDisplay }
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1
        // Minimize unused video work. No screen output or microphone output is registered.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let output = AudioOutput(receive: receive, onFailure: onFailure)
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
        self.output = output
        self.stream = stream
        do {
            try await stream.startCapture()
            guard generation == token else { throw CancellationError() }
        }
        catch { await stop(); throw error }
    }

    func stop() async {
        generation = UUID()
        let oldStream = stream
        output?.disable()
        stream = nil
        output = nil
        try? await oldStream?.stopCapture()
    }
}

/// Serial capture callbacks forward directly to the recognizer, avoiding an audio queue on MainActor.
private final class AudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    private let lock = NSLock()
    private var receive: ((CMSampleBuffer) -> Void)?
    private let onFailure: @MainActor (Error) -> Void

    init(receive: @escaping (CMSampleBuffer) -> Void, onFailure: @escaping @MainActor (Error) -> Void) {
        self.receive = receive
        self.onFailure = onFailure
    }

    func disable() { lock.lock(); receive = nil; lock.unlock() }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        lock.lock()
        let receiver = receive
        lock.unlock()
        receiver?(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let active = receive != nil
        lock.unlock()
        if active { Task { @MainActor in onFailure(error) } }
    }
}
