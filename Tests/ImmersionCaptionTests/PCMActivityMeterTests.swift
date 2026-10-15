import XCTest
import AVFoundation
import CoreMedia
@testable import ImmersionCaption

final class PCMActivityMeterTests: XCTestCase {
    func testSilenceAndAntiphaseStereoAreMeasuredWithoutChannelCancellation() throws {
        XCTAssertEqual(try measure(.pcmFormatFloat32, interleaved: true, silent: true), 0)
        XCTAssertEqual(try measure(.pcmFormatFloat32, interleaved: true), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(try measure(.pcmFormatFloat32, interleaved: false), 0.5, accuracy: 0.000_001)
    }

    func testOtherNativePCMRepresentationsHaveTheSameNormalizedLevel() throws {
        for format in [AVAudioCommonFormat.pcmFormatFloat64, .pcmFormatInt16, .pcmFormatInt32] {
            for interleaved in [true, false] {
                XCTAssertEqual(try measure(format, interleaved: interleaved), 0.5, accuracy: 0.000_001)
            }
        }
    }

    func testNonfinitePCMIsRejectedInsteadOfReportedAsSilence() throws {
        let sample = try makeSample(.pcmFormatFloat32, interleaved: true, invalid: true)
        XCTAssertThrowsError(try PCMActivityMeter().rms(of: sample))
    }

    func testInvalidSamplesAreRejected() throws {
        let sample = try makeSample(.pcmFormatFloat32, interleaved: true)
        CMSampleBufferInvalidate(sample)
        XCTAssertThrowsError(try PCMActivityMeter().rms(of: sample))
    }

    private func measure(_ common: AVAudioCommonFormat, interleaved: Bool,
                         silent: Bool = false) throws -> Double {
        try PCMActivityMeter().rms(of: makeSample(common, interleaved: interleaved, silent: silent))
    }

    private func makeSample(_ common: AVAudioCommonFormat, interleaved: Bool,
                            silent: Bool = false, invalid: Bool = false) throws -> CMSampleBuffer {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: common,
            sampleRate: 48_000, channels: 2, interleaved: interleaved))
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        pcm.frameLength = 480
        let buffers = UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList)
        for (plane, buffer) in buffers.enumerated() {
            let data = try XCTUnwrap(buffer.mData)
            let bytes = Int(format.streamDescription.pointee.mBitsPerChannel / 8)
            for index in 0..<(Int(buffer.mDataByteSize) / bytes) {
                let channel = interleaved ? index % 2 : plane
                let value: Double = silent ? 0 : (channel == 0 ? 0.5 : -0.5)
                switch common {
                case .pcmFormatFloat32:
                    data.storeBytes(of: invalid ? Float.nan : Float(value), toByteOffset: index * bytes, as: Float.self)
                case .pcmFormatFloat64:
                    data.storeBytes(of: value, toByteOffset: index * bytes, as: Double.self)
                case .pcmFormatInt16:
                    data.storeBytes(of: Int16(value * 32768), toByteOffset: index * bytes, as: Int16.self)
                case .pcmFormatInt32:
                    data.storeBytes(of: Int32(value * 2147483648), toByteOffset: index * bytes, as: Int32.self)
                default: XCTFail("Unexpected fixture format")
                }
            }
        }
        return try XCTUnwrap(PCMBufferConverter(format: format.streamDescription.pointee).convert(pcm.audioBufferList))
    }
}
