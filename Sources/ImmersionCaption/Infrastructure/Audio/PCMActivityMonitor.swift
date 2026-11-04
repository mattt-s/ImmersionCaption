import CoreAudio
import CoreMedia
import Foundation

/// Detects output above a conservative -80 dBFS peak floor. No audio is retained.
/// Each capture run gets a fresh instance; the lock protects its timestamp across
/// capture and MainActor polling. PCM inspection stays on the capture callback queue.
final class PCMActivityMonitor: AudioActivityMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var lastActivity: TimeInterval?
    private let now: @Sendable () -> TimeInterval
    private let threshold = 0.0001

    init(now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    var lastAudibleTime: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return lastActivity
    }

    func consume(_ sample: CMSampleBuffer) {
        guard hasSignal(sample) else { return }
        let time = now()
        lock.lock(); lastActivity = time; lock.unlock()
    }

    private func hasSignal(_ sample: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetNumSamples(sample) > 0 else { return false }
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return true }
        let format = pointer.pointee
        guard format.mFormatID == kAudioFormatLinearPCM, format.mChannelsPerFrame > 0 else { return true }
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(format.mChannelsPerFrame)
        let count = planar ? channels : 1
        let stride = Int(format.mBytesPerFrame) / (planar ? 1 : channels)
        guard count <= 32, [1, 2, 3, 4, 8].contains(stride) else { return true }
        let buffers = AudioBufferList.allocate(maximumBuffers: count)
        defer { buffers.unsafeMutablePointer.deallocate() }
        let size = MemoryLayout<AudioBufferList>.size + (count - 1) * MemoryLayout<AudioBuffer>.size
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,
            bufferListSizeNeededOut: nil, bufferListOut: buffers.unsafeMutablePointer,
            bufferListSize: size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: &block) == noErr else { return true }
        return withExtendedLifetime(block) {
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let bytes = data.assumingMemoryBound(to: UInt8.self)
                for offset in Swift.stride(from: 0, to: Int(buffer.mDataByteSize) - stride + 1, by: stride) {
                    // Load bytes explicitly: handles unaligned, planar/interleaved, and endian PCM.
                    var bits: UInt64 = 0
                    for index in 0..<stride {
                        let position = format.mFormatFlags & kAudioFormatFlagIsBigEndian != 0 ? stride - 1 - index : index
                        bits |= UInt64(bytes[offset + index]) << (position * 8)
                    }
                    guard let value = normalizedValue(bits, bytes: stride, format: format) else { return true }
                    if value.isFinite && abs(value) > threshold { return true }
                }
            }
            return false
        }
    }

    /// Unknown formats are treated conservatively as activity, avoiding lost captions.
    private func normalizedValue(_ bits: UInt64, bytes: Int, format: AudioStreamBasicDescription) -> Double? {
        let depth = Int(format.mBitsPerChannel)
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            if depth == 32 && bytes == 4 { return Double(Float(bitPattern: UInt32(bits))) }
            if depth == 64 && bytes == 8 { return Double(bitPattern: bits) }
            return nil
        }
        guard depth > 0, depth <= 32, depth <= bytes * 8 else { return nil }
        let aligned = format.mFormatFlags & kAudioFormatFlagIsAlignedHigh != 0
            ? bits >> (bytes * 8 - depth) : bits
        let mask = (UInt64(1) << depth) - 1
        let raw = aligned & mask
        let midpoint = Int64(1) << (depth - 1)
        let value: Int64
        if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 {
            value = Int64(raw) - (raw & UInt64(midpoint) != 0 ? Int64(1) << depth : 0)
        } else {
            value = Int64(raw) - midpoint
        }
        return Double(value) / Double(midpoint)
    }
}
