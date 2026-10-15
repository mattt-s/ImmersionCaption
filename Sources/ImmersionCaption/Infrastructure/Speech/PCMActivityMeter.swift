import AVFoundation
import CoreMedia

/// Measures each channel separately so antiphase stereo cannot cancel into false silence.
/// Reads owning Core Media audio without copying the PCM payload or retaining it afterward.
struct PCMActivityMeter {
    func rms(of sample: CMSampleBuffer) throws -> Double {
        guard sample.isValid,
              let description = CMSampleBufferGetFormatDescription(sample),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mChannelsPerFrame > 0, format.mChannelsPerFrame <= 64,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mFormatFlags & kAudioFormatFlagIsPacked != 0 else {
            throw SpeechError.unsupportedAudioFormat
        }
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let isInteger = format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0
        guard (isFloat && [32, 64].contains(format.mBitsPerChannel)) ||
              (isInteger && [16, 32].contains(format.mBitsPerChannel)) else {
            throw SpeechError.unsupportedAudioFormat
        }
        let planar = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let planes = planar ? Int(format.mChannelsPerFrame) : 1
        // Core Media expects the list size for the actual number of audio planes.
        let capacity = MemoryLayout<AudioBufferList>.size + (planes - 1) * MemoryLayout<AudioBuffer>.stride
        let storage = UnsafeMutableRawPointer.allocate(byteCount: capacity,
                                                       alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedAudio: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,
            bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: capacity,
            blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedAudio)
        guard status == noErr else { throw SpeechError.unsupportedAudioFormat }
        // The retained block buffer owns all plane pointers until measurement completes.
        return try withExtendedLifetime(retainedAudio) {
            var loudest: Double = 0
            for buffer in UnsafeMutableAudioBufferListPointer(list) {
                guard let data = buffer.mData, buffer.mNumberChannels > 0 else {
                    throw SpeechError.unsupportedAudioFormat
                }
                let channels = Int(buffer.mNumberChannels)
                let bytes = Int(format.mBitsPerChannel / 8)
                let count = Int(buffer.mDataByteSize) / bytes
                guard count > 0, count % channels == 0 else {
                    throw SpeechError.unsupportedAudioFormat
                }
                for channel in 0..<channels {
                    var sum: Double = 0
                    for index in stride(from: channel, to: count, by: channels) {
                        let value: Double
                        switch (isFloat, format.mBitsPerChannel) {
                        case (true, 32): value = Double(data.load(fromByteOffset: index * bytes, as: Float.self))
                        case (true, 64): value = data.load(fromByteOffset: index * bytes, as: Double.self)
                        case (false, 16): value = Double(data.load(fromByteOffset: index * bytes, as: Int16.self)) / 32768
                        default: value = Double(data.load(fromByteOffset: index * bytes, as: Int32.self)) / 2147483648
                        }
                        guard value.isFinite else { throw SpeechError.unsupportedAudioFormat }
                        sum += value * value
                    }
                    guard sum.isFinite else { throw SpeechError.unsupportedAudioFormat }
                    loudest = max(loudest, sqrt(sum / Double(count / channels)))
                }
            }
            return loudest
        }
    }
}
