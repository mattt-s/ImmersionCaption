import XCTest
import AVFoundation
import CoreMedia
@testable import ImmersionCaption

final class PCMActivityMonitorTests: XCTestCase {
    func testSilentPCMDoesNotCountAsActivityAndNegativeSamplesDo() throws {
        let (pcm, converter) = try fixture(.pcmFormatFloat32, interleaved: true)
        let monitor = PCMActivityMonitor(now: { 42 })
        monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
        XCTAssertNil(monitor.lastAudibleTime)
        let data = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)[0].mData!
        data.assumingMemoryBound(to: Float.self)[1] = -0.25
        monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
        XCTAssertEqual(monitor.lastAudibleTime, 42)
        data.assumingMemoryBound(to: Float.self)[1] = 0
        monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
        XCTAssertEqual(monitor.lastAudibleTime, 42, "Silence must not move the activity deadline")
    }

    func testNoninterleavedActivityInSecondChannelIsDetected() throws {
        let (pcm, converter) = try fixture(.pcmFormatFloat32, interleaved: false)
        pcm.floatChannelData![1][0] = 0.4
        let monitor = PCMActivityMonitor(now: { 8 })
        monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
        XCTAssertEqual(monitor.lastAudibleTime, 8)
    }

    func testQuietFloorAndNonfiniteFloatsDoNotCountAsSignal() throws {
        let (pcm, converter) = try fixture(.pcmFormatFloat32, interleaved: true)
        let data = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)[0].mData!.assumingMemoryBound(to: Float.self)
        data[0] = 0.00001
        data[1] = .nan
        data[2] = .infinity
        let monitor = PCMActivityMonitor(now: { 7 })
        monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
        XCTAssertNil(monitor.lastAudibleTime)
        data[0] = 0.01
        monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
        XCTAssertEqual(monitor.lastAudibleTime, 7)
    }

    func testFloat64AndSignedInt16PCM() throws {
        for format in [AVAudioCommonFormat.pcmFormatFloat64, .pcmFormatInt16] {
            let (pcm, converter) = try fixture(format, interleaved: false)
            let monitor = PCMActivityMonitor(now: { 9 })
            monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
            XCTAssertNil(monitor.lastAudibleTime)
            if format == .pcmFormatFloat64 {
                let plane = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)[1]
                plane.mData!.assumingMemoryBound(to: Double.self)[0] = -0.5
            }
            else { pcm.int16ChannelData![1][0] = -16384 }
            monitor.consume(try XCTUnwrap(converter.convert(pcm.audioBufferList)))
            XCTAssertEqual(monitor.lastAudibleTime, 9)
        }
    }

    private func fixture(_ common: AVAudioCommonFormat, interleaved: Bool) throws -> (AVAudioPCMBuffer, PCMBufferConverter) {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: common, sampleRate: 48000, channels: 2, interleaved: interleaved))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        pcm.frameLength = 480
        for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
            memset(buffer.mData!, 0, Int(buffer.mDataByteSize))
        }
        return (pcm, try PCMBufferConverter(format: format.streamDescription.pointee))
    }
}
