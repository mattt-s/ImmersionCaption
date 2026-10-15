import CoreAudio
import CoreMedia

/// Copies HAL-owned PCM into an owning sample buffer before the audio callback returns.
/// Confined to one capture queue; timestamps advance by frames at the tap's native sample rate.
final class PCMBufferConverter {
    private let format: AudioStreamBasicDescription
    private let description: CMAudioFormatDescription
    private var nextFrame: Int64 = 0

    init(format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate.isFinite, format.mSampleRate > 0,
              format.mSampleRate <= Double(Int32.max),
              format.mSampleRate.rounded() == format.mSampleRate,
              format.mChannelsPerFrame > 0, format.mBytesPerFrame > 0,
              format.mFramesPerPacket == 1 else { throw AudioCaptureError.invalidFormat }
        var format = format
        var description: CMAudioFormatDescription?
        try checkAudioStatus(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
            asbd: &format, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description), operation: "describe the audio format")
        guard let description else { throw AudioCaptureError.invalidFormat }
        self.format = format
        self.description = description
    }

    /// Returns nil for an empty callback. Rejects mismatched planes instead of reading past memory.
    func convert(_ input: UnsafePointer<AudioBufferList>) throws -> CMSampleBuffer? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let expectedBuffers = planar ? Int(format.mChannelsPerFrame) : 1
        guard buffers.count == expectedBuffers else { throw AudioCaptureError.invalidFormat }
        guard let first = buffers.first else { return nil }
        let byteCount = first.mDataByteSize
        guard byteCount > 0 else { return nil }
        guard byteCount % format.mBytesPerFrame == 0 else { throw AudioCaptureError.invalidFormat }
        for buffer in buffers {
            guard buffer.mData != nil, buffer.mDataByteSize == byteCount,
                  buffer.mNumberChannels == (planar ? 1 : format.mChannelsPerFrame) else {
                throw AudioCaptureError.invalidFormat
            }
        }
        let frames = Int(byteCount / format.mBytesPerFrame)
        // Core Media validates PCM frame counts against duration. A rounded nanosecond
        // approximation of 1/48,000 fails that check; preserve the exact sample clock.
        let sampleRate = Int32(format.mSampleRate)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: sampleRate),
            presentationTimeStamp: CMTime(value: nextFrame, timescale: sampleRate),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        try checkAudioStatus(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil,
            dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: description,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample),
            operation: "create an audio buffer")
        guard let sample else { throw AudioCaptureError.invalidFormat }
        try checkAudioStatus(CMSampleBufferSetDataBufferFromAudioBufferList(sample,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, bufferList: input),
            operation: "copy system audio")
        try checkAudioStatus(CMSampleBufferSetDataReady(sample), operation: "prepare system audio")
        nextFrame += Int64(frames)
        return sample
    }
}
