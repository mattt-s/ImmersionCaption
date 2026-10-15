import CoreAudio
import CoreMedia
import Foundation

/// Synchronizes stop with delivery. HAL invokes this on one serial queue, synchronously,
/// so callbacks do not create a growing task queue. Only failures hop to MainActor.
final class AudioTapOutput {
    private let lock = NSLock()
    private var receive: ((CMSampleBuffer) -> Void)?
    private var stopped = false
    private var failed = false
    private let onFailure: @MainActor (Error) -> Void

    init(receive: @escaping (CMSampleBuffer) -> Void,
         onFailure: @escaping @MainActor (Error) -> Void) {
        self.receive = receive
        self.onFailure = onFailure
    }

    func disable() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        receive = nil
    }

    func consume(_ input: UnsafePointer<AudioBufferList>, converter: PCMBufferConverter) {
        lock.lock()
        guard !stopped, !failed else { lock.unlock(); return }
        do {
            if let sample = try converter.convert(input) { receive?(sample) }
            lock.unlock()
        } catch {
            lock.unlock()
            fail(error)
        }
    }

    func fail(_ error: Error) {
        lock.lock()
        guard !stopped, !failed else { lock.unlock(); return }
        failed = true
        receive = nil
        lock.unlock()
        Task { @MainActor [self] in
            guard !isStopped else { return }
            onFailure(error)
        }
    }

    private var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }
}
