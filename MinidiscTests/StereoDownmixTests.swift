import AudioToolbox
import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio
#endif
import Foundation
import Testing
@testable import Minidisc

@Suite("Stereo downmix")
struct StereoDownmixTests {
    @Test("5.1 folds down with centre and surrounds at -3 dB, LFE dropped, never louder than the input")
    func fiveOneMatrix() {
        let labels = DownmixMatrix.defaultLabels(channels: 6)
        let matrix = DownmixMatrix(labels: labels)
        let scale: Float = 1 / (1 + 0.7071 + 0.7071)
        #expect(abs(matrix.left[0] - scale) < 1e-4)
        #expect(matrix.right[0] == 0)
        #expect(abs(matrix.left[2] - 0.7071 * scale) < 1e-4)
        #expect(matrix.left[3] == 0 && matrix.right[3] == 0)
        #expect(abs(matrix.right[5] - 0.7071 * scale) < 1e-4)
        #expect(abs(matrix.left.reduce(0, +) - 1) < 1e-4)
        #expect(abs(matrix.right.reduce(0, +) - 1) < 1e-4)
    }

    @Test("A track's declared layout decides which channel is which")
    func declaredLayout() {
        var aac = AudioChannelLayout()
        aac.mChannelLayoutTag = kAudioChannelLayoutTag_AAC_5_1
        let labels = withUnsafePointer(to: &aac) { DownmixMatrix.channelLabels(of: $0) }
        #expect(labels == [kAudioChannelLabel_Center, kAudioChannelLabel_Left, kAudioChannelLabel_Right,
                           kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround, kAudioChannelLabel_LFEScreen])

        var wave = AudioChannelLayout()
        wave.mChannelLayoutTag = kAudioChannelLayoutTag_WAVE_5_1_A
        let waveLabels = withUnsafePointer(to: &wave) { DownmixMatrix.channelLabels(of: $0) }
        #expect(waveLabels == DownmixMatrix.defaultLabels(channels: 6))
    }

    @Test("Processing writes the fold-down to the first two channels and silences the rest")
    func processing() {
        let parameters = DownmixParameters()
        let processor = StereoDownmixProcessor(labels: nil, parameters: parameters)
        processor.prepare(channels: 6, interleaved: false)
        // Only the centre channel carries signal.
        let buffers = TestBuffers(channels: 6, frames: 8) { channel, _ in channel == 2 ? 1 : 0 }
        processor.process(buffers.list, frames: buffers.frames)
        let expected: Float = 0.7071 / (1 + 0.7071 + 0.7071)
        #expect(buffers.samples(0).allSatisfy { abs($0 - expected) < 1e-4 })
        #expect(buffers.samples(1).allSatisfy { abs($0 - expected) < 1e-4 })
        for channel in 2..<6 { #expect(buffers.samples(channel).allSatisfy { $0 == 0 }) }
    }

    @Test("Stereo, and anything with the setting off, passes through")
    func passThrough() {
        let parameters = DownmixParameters()
        let stereo = StereoDownmixProcessor(labels: nil, parameters: parameters)
        stereo.prepare(channels: 2, interleaved: false)
        let pair = TestBuffers(channels: 2, frames: 4) { channel, _ in Float(channel + 1) }
        stereo.process(pair.list, frames: pair.frames)
        #expect(pair.samples(1) == [2, 2, 2, 2])

        parameters.isEnabled = false
        let surround = StereoDownmixProcessor(labels: nil, parameters: parameters)
        surround.prepare(channels: 6, interleaved: false)
        let six = TestBuffers(channels: 6, frames: 4) { channel, _ in Float(channel) }
        surround.process(six.list, frames: six.frames)
        #expect(six.samples(5) == [5, 5, 5, 5])
    }

    @Test("A multichannel track needs the tap only while the fold-down is on")
    func tapRouting() {
        #expect(AVPlayerEngine.requiresAudioTap(linearGain: 1, equalizerEnabled: false, channelCount: 6, downmixEnabled: true))
        #expect(!AVPlayerEngine.requiresAudioTap(linearGain: 1, equalizerEnabled: false, channelCount: 6, downmixEnabled: false))
        #expect(!AVPlayerEngine.requiresAudioTap(linearGain: 1, equalizerEnabled: false, channelCount: 2, downmixEnabled: true))
    }
}
