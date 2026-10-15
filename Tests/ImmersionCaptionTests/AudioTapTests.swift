import XCTest
import AVFoundation
import CoreMedia
@testable import ImmersionCaption

final class PCMBufferConverterTests: XCTestCase {
    func testInterleavedStereoCopiesHALMemoryAndKeepsFrameTiming() throws {
        let pcm = makePCM(interleaved: true)
        let converter = try PCMBufferConverter(format: pcm.format.streamDescription.pointee)
        let data = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)[0].mData!
        data.assumingMemoryBound(to: Float.self)[0] = 0.75
        let first = try XCTUnwrap(converter.convert(pcm.audioBufferList))
        // HAL is allowed to reuse its buffer immediately after delivery.
        data.assumingMemoryBound(to: Float.self)[0] = -0.25
        var copied: Float = 0
        let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(first))
        XCTAssertEqual(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: 4,
                                                 destination: &copied), noErr)
        XCTAssertEqual(copied, 0.75)
        XCTAssertTrue(CMSampleBufferDataIsReady(first))
        XCTAssertEqual(CMSampleBufferGetNumSamples(first), 480)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(first).seconds, 0, accuracy: 0.000_001)
        let second = try XCTUnwrap(converter.convert(pcm.audioBufferList))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(second).seconds, 0.01, accuracy: 0.000_001)
        XCTAssertEqual(CMSampleBufferGetDuration(first).seconds, 0.01, accuracy: 0.000_001)
    }

    func testNoninterleavedStereoPreservesBothPlanes() throws {
        let pcm = makePCM(interleaved: false)
        let converter = try PCMBufferConverter(format: pcm.format.streamDescription.pointee)
        pcm.floatChannelData![0][0] = 0.5
        pcm.floatChannelData![1][0] = -0.5
        let sample = try XCTUnwrap(converter.convert(pcm.audioBufferList))
        let planes = AudioBufferList.allocate(maximumBuffers: 2)
        defer { planes.unsafeMutablePointer.deallocate() }
        var retained: CMBlockBuffer?
        XCTAssertEqual(CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,
            bufferListSizeNeededOut: nil, bufferListOut: planes.unsafeMutablePointer,
            bufferListSize: MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: 0, blockBufferOut: &retained), noErr)
        XCTAssertEqual(planes.count, 2)
        XCTAssertEqual(planes[0].mData!.assumingMemoryBound(to: Float.self)[0], 0.5)
        XCTAssertEqual(planes[1].mData!.assumingMemoryBound(to: Float.self)[0], -0.5)
    }

    func testRejectsInvalidFormats() {
        var format = makePCM(interleaved: true).format.streamDescription.pointee
        format.mSampleRate = .nan
        XCTAssertThrowsError(try PCMBufferConverter(format: format))
        format.mSampleRate = 48_000
        format.mBytesPerFrame = 0
        XCTAssertThrowsError(try PCMBufferConverter(format: format))
    }

    func testEmptyCallbackDoesNotAdvanceClock() throws {
        let pcm = makePCM(interleaved: true)
        let converter = try PCMBufferConverter(format: pcm.format.streamDescription.pointee)
        pcm.frameLength = 0
        XCTAssertNil(try converter.convert(pcm.audioBufferList))
        pcm.frameLength = 480
        let sample = try XCTUnwrap(converter.convert(pcm.audioBufferList))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(sample).seconds, 0)
    }

    func testRejectsTruncatedOrMismatchedPlanes() throws {
        let pcm = makePCM(interleaved: false)
        let converter = try PCMBufferConverter(format: pcm.format.streamDescription.pointee)
        // AVAudioPCMBuffer refreshes byte counts when its accessor is called. Keep the
        // raw list so these malformed HAL fixtures reach the converter unchanged.
        let input = pcm.mutableAudioBufferList
        let buffers = UnsafeMutableAudioBufferListPointer(input)
        buffers[1].mDataByteSize -= 4
        XCTAssertThrowsError(try converter.convert(input))
        buffers[1].mDataByteSize += 4
        buffers[0].mDataByteSize -= 1
        XCTAssertThrowsError(try converter.convert(input))
        buffers[0].mDataByteSize += 1
    }

    private func makePCM(interleaved: Bool) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                   channels: 2, interleaved: interleaved)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        pcm.frameLength = 480
        return pcm
    }
}

@MainActor
final class AudioTapOutputTests: XCTestCase {
    func testDisablePreventsFurtherAudioDelivery() throws {
        let pcm = makePCM()
        let converter = try PCMBufferConverter(format: pcm.format.streamDescription.pointee)
        var deliveries = 0
        let output = AudioTapOutput(receive: { _ in deliveries += 1 }, onFailure: { _ in XCTFail() })
        output.consume(pcm.audioBufferList, converter: converter)
        output.disable()
        output.consume(pcm.audioBufferList, converter: converter)
        XCTAssertEqual(deliveries, 1)
    }

    func testInvalidAudioReportsOneFailureAndStopsDelivery() async throws {
        let pcm = makePCM()
        let converter = try PCMBufferConverter(format: pcm.format.streamDescription.pointee)
        var deliveries = 0
        let failure = expectation(description: "Invalid PCM reported")
        failure.assertForOverFulfill = true
        let output = AudioTapOutput(receive: { _ in deliveries += 1 }, onFailure: { _ in failure.fulfill() })
        let input = pcm.mutableAudioBufferList
        let buffers = UnsafeMutableAudioBufferListPointer(input)
        buffers[0].mDataByteSize -= 1
        output.consume(input, converter: converter)
        output.consume(input, converter: converter)
        buffers[0].mDataByteSize += 1
        output.consume(input, converter: converter)
        await fulfillment(of: [failure], timeout: 1)
        XCTAssertEqual(deliveries, 0)
    }

    func testStopSuppressesQueuedFailure() async {
        var failures = 0
        let output = AudioTapOutput(receive: { _ in XCTFail() }, onFailure: { _ in failures += 1 })
        output.fail(AudioCaptureError.formatChanged)
        output.disable()
        await Task.yield()
        XCTAssertEqual(failures, 0)
    }

    private func makePCM() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                   channels: 2, interleaved: true)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        pcm.frameLength = 480
        return pcm
    }
}
