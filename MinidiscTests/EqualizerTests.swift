import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio
#endif
import Foundation
import Testing
@testable import Minidisc

@Suite("Equalizer")
struct EqualizerTests {
    private let sampleRate: Float = 44100

    /// Peak amplitude of a sine after the processor has settled.
    private func outputPeak(frequency: Float, processor: EqualizerProcessor, frames: Int = 44100) -> Float {
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer { left.deallocate(); right.deallocate() }
        for i in 0..<frames {
            let sample = 0.25 * sin(2 * Float.pi * frequency * Float(i) / sampleRate)
            left[i] = sample; right[i] = sample
        }
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: left)
        list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: right)
        processor.process(list, frames: frames)
        return (frames / 2..<frames).map { abs(left[$0]) }.max() ?? 0
    }

    private func processor(gains: [Float], preamp: Float = 0, enabled: Bool = true) -> EqualizerProcessor {
        let parameters = EqualizerParameters()
        var snapshot = EqualizerParameters.Snapshot()
        snapshot.isEnabled = enabled
        snapshot.preampDB = preamp
        for (band, gain) in gains.enumerated() { snapshot.gainsDB[band] = gain }
        parameters.update(snapshot)
        let processor = EqualizerProcessor(parameters: parameters)
        processor.prepare(sampleRate: Double(sampleRate), channels: 2, interleaved: false)
        return processor
    }

    @Test func flatOrDisabledLeavesAudioUntouched() {
        #expect(abs(outputPeak(frequency: 1000, processor: processor(gains: EqualizerPreset.flat.gains)) - 0.25) < 0.001)
        #expect(abs(outputPeak(frequency: 1000, processor: processor(gains: EqualizerPreset.bassBoost.gains, enabled: false)) - 0.25) < 0.001)
    }

    @Test func boostingABandRaisesItsFrequencyOnly() {
        var gains = [Float](repeating: 0, count: 10)
        gains[5] = 6 // 1 kHz
        let boosted = outputPeak(frequency: 1000, processor: processor(gains: gains))
        #expect(abs(20 * log10(boosted / 0.25) - 6) < 0.5)
        let far = outputPeak(frequency: 8000, processor: processor(gains: gains))
        #expect(abs(20 * log10(far / 0.25)) < 1)
    }

    @Test func preampLowersEverything() {
        let quiet = outputPeak(frequency: 440, processor: processor(gains: EqualizerPreset.flat.gains, preamp: -6))
        #expect(abs(20 * log10(quiet / 0.25) + 6) < 0.3)
    }

    @Test func presetsLeaveHeadroomForTheirBiggestBoost() {
        for preset in EqualizerPreset.allCases {
            #expect(preset.gains.count == Equalizer.bandCount)
            #expect(preset.preamp <= 0)
            #expect(preset.preamp == -max(0, preset.gains.max()!))
        }
    }

    @MainActor
    @Test func settingsPersistAndPublish() throws {
        let defaults = try #require(UserDefaults(suiteName: "EqualizerTests.\(UUID())"))
        let parameters = EqualizerParameters()
        let settings = EqualizerSettings(defaults: defaults, parameters: parameters)
        settings.isEnabled = true
        settings.apply(.vocal)
        settings.setGain(3, band: 0)
        #expect(settings.preset == nil)
        #expect(parameters.snapshot.isEnabled)
        #expect(parameters.snapshot.gainsDB[0] == 3)
        let reloaded = EqualizerSettings(defaults: defaults, parameters: EqualizerParameters())
        #expect(reloaded.gains == settings.gains)
        #expect(reloaded.isEnabled)
        #expect(reloaded.preset == nil)
    }
}
