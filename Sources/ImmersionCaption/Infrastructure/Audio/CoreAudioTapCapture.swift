import CoreAudio
import CoreMedia
import Foundation
import OSLog

/// Captures process output via a private Core Audio tap. No display or microphone is opened.
@MainActor
final class CoreAudioTapCapture: SystemAudioCapturing {
    private var run: AudioTapRun?
    private var generation = UUID()

    func start(receive: @escaping (CMSampleBuffer) -> Void,
               onFailure: @escaping @MainActor (Error) -> Void) async throws {
        generation = UUID()
        let token = generation
        let oldRun = run
        run = nil
        await oldRun?.stop()
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        let run = AudioTapRun(receive: receive, onFailure: onFailure)
        self.run = run
        do {
            try await run.start()
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
        } catch {
            await run.stop()
            if generation == token { self.run = nil }
            throw error
        }
    }

    func stop() async {
        generation = UUID()
        let oldRun = run
        run = nil
        await oldRun?.stop()
    }
}

/// Each run owns its resources on a serial control queue. Permission/device work stays off
/// MainActor; stop disables callbacks first, then destroys IOProc → aggregate → tap.
private final class AudioTapRun: @unchecked Sendable {
    private let controlQueue = DispatchQueue(label: "app.ImmersionCaption.audio.control", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "app.ImmersionCaption.audio.samples", qos: .userInitiated)
    private let output: AudioTapOutput
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var formatListener: AudioObjectPropertyListenerBlock?
    private static let logger = Logger(subsystem: "app.ImmersionCaption", category: "AudioCapture")

    init(receive: @escaping (CMSampleBuffer) -> Void,
         onFailure: @escaping @MainActor (Error) -> Void) {
        output = AudioTapOutput(receive: receive, onFailure: onFailure)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controlQueue.async { [self] in
                do { try createAndStart(); continuation.resume() }
                catch { destroy(); continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        output.disable()
        await withCheckedContinuation { continuation in
            controlQueue.async { [self] in destroy(); continuation.resume() }
        }
    }

    private func createAndStart() throws {
        var pid = ProcessInfo.processInfo.processIdentifier
        var processID = AudioObjectID(kAudioObjectUnknown)
        var address = property(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try checkAudioStatus(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
            &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &processID),
            operation: "identify this process")
        // An app with no playback may have no HAL process object yet; it produces no audio to exclude.
        let excluded = processID == kAudioObjectUnknown ? [] : [processID]
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.name = "ImmersionCaption system audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try checkAudioStatus(AudioHardwareCreateProcessTap(description, &tapID), operation: "create an audio tap")

        var format = AudioStreamBasicDescription()
        address = property(kAudioTapPropertyFormat)
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try checkAudioStatus(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format),
                             operation: "read the audio tap format")
        let converter = try PCMBufferConverter(format: format)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ImmersionCaption private audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            // Start immediately, including during silence; do not wait for a tapped app to play.
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        // Tap-only aggregate: no physical input or output subdevice, and no default-device changes.
        try checkAudioStatus(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID),
                             operation: "create a private audio device")
        let output = output
        let tapID = tapID
        let initialFormat = format
        let listener: AudioObjectPropertyListenerBlock = { _, _ in
            var current = AudioStreamBasicDescription()
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &current)
            guard status == noErr else {
                output.fail(AudioCaptureError.hardware(operation: "read the changed audio format", status: status))
                return
            }
            // HAL can notify without changing the format, including during startup.
            if !Self.sameFormat(current, initialFormat) { output.fail(AudioCaptureError.formatChanged) }
        }
        address = property(kAudioTapPropertyFormat)
        try checkAudioStatus(AudioObjectAddPropertyListenerBlock(tapID, &address, controlQueue, listener),
                             operation: "monitor the audio format")
        formatListener = listener
        try checkAudioStatus(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, deviceID, audioQueue) {
            _, input, _, _, _ in output.consume(input, converter: converter)
        }, operation: "register audio delivery")
        try checkAudioStatus(AudioDeviceStart(deviceID, ioProcID), operation: "start system audio recording")
    }

    /// Attempts every cleanup step, including after partially completed startup.
    private func destroy() {
        if let ioProcID {
            logCleanup(AudioDeviceStop(deviceID, ioProcID))
            logCleanup(AudioDeviceDestroyIOProcID(deviceID, ioProcID))
            self.ioProcID = nil
        }
        if let formatListener {
            var address = property(kAudioTapPropertyFormat)
            logCleanup(AudioObjectRemovePropertyListenerBlock(tapID, &address, controlQueue, formatListener))
            self.formatListener = nil
        }
        if deviceID != kAudioObjectUnknown {
            logCleanup(AudioHardwareDestroyAggregateDevice(deviceID))
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            logCleanup(AudioHardwareDestroyProcessTap(tapID))
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func property(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func logCleanup(_ status: OSStatus) {
        if status != noErr { Self.logger.error("Audio resource cleanup returned status \(status)") }
    }

    private static func sameFormat(_ lhs: AudioStreamBasicDescription,
                                   _ rhs: AudioStreamBasicDescription) -> Bool {
        lhs.mSampleRate == rhs.mSampleRate && lhs.mFormatID == rhs.mFormatID &&
        lhs.mFormatFlags == rhs.mFormatFlags && lhs.mBytesPerPacket == rhs.mBytesPerPacket &&
        lhs.mFramesPerPacket == rhs.mFramesPerPacket && lhs.mBytesPerFrame == rhs.mBytesPerFrame &&
        lhs.mChannelsPerFrame == rhs.mChannelsPerFrame && lhs.mBitsPerChannel == rhs.mBitsPerChannel
    }
}
