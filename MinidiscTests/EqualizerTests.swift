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

    @Test func tenBandsFrom31HzTo16kHz() {
        #expect(Equalizer.frequencies == [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
        #expect(Equalizer.frequencies.count == Equalizer.bandCount)
        #expect(Equalizer.q == 1.41)
    }

    /// The RBJ cookbook peaking filter, worked in Double as an independent reference.
    private func reference(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> [Double] {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let a0 = 1 + alpha / a
        return [(1 + alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha * a) / a0, -2 * cos(w0) / a0, (1 - alpha / a) / a0]
    }

    @Test(arguments: [Float(31), 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000])
    func bandCoefficientsMatchTheCookbook(frequency: Float) {
        for gain: Float in [-12, -3, 6, 12] {
            let c = EqualizerProcessor.peakingCoefficients(frequency: frequency, gainDB: gain, q: Equalizer.q, sampleRate: 48000)
            let expected = reference(frequency: Double(frequency), gainDB: Double(gain), q: Double(Equalizer.q), sampleRate: 48000)
            for (value, wanted) in zip([c.b0, c.b1, c.b2, c.a1, c.a2], expected) {
                #expect(abs(Double(value) - wanted) < 1e-5)
            }
            // On its own, each band reaches its gain exactly at its centre frequency.
            var gains = [Float](repeating: 0, count: Equalizer.bandCount)
            gains[Equalizer.frequencies.firstIndex(of: frequency)!] = gain
            #expect(abs(Equalizer.response(at: frequency, gains: gains) - gain) < 0.01)
        }
    }

    @Test func flatBandsAreTransparent() {
        let c = EqualizerProcessor.peakingCoefficients(frequency: 1000, gainDB: 0, q: Equalizer.q, sampleRate: 44100)
        #expect(abs(c.b0 - 1) < 1e-6)
        #expect(abs(c.b1 - c.a1) < 1e-6)
        #expect(abs(c.b2 - c.a2) < 1e-6)
        #expect(abs(Equalizer.response(at: 3000, gains: EqualizerPreset.flat.gains)) < 1e-4)
    }

    @Test func the16kHzBandIsLeftOutAtLowSampleRates() {
        // At 32 kHz, 16 kHz is the Nyquist limit; the processor must skip it rather than blow up.
        var gains = [Float](repeating: 0, count: Equalizer.bandCount)
        gains[9] = 12
        let processor = processor(gains: gains)
        processor.prepare(sampleRate: 32000, channels: 2, interleaved: false)
        #expect(processor.refreshIfNeeded())
        #expect(abs(outputPeak(frequency: 1000, processor: processor) - 0.25) < 0.01)
    }

    @MainActor
    @Test func curvesSavedBeforeTheBandMoveLoadUnchanged() throws {
        let defaults = try #require(UserDefaults(suiteName: "EqualizerTests.\(UUID())"))
        // A curve as the 32/64 Hz build stored it: ten Doubles, a preamp and no preset.
        let saved: [Double] = [4.5, 3, 1, 0, -1, 0, 1.5, 2, 3, 3.5]
        defaults.set(true, forKey: "equalizer.enabled")
        defaults.set(saved, forKey: "equalizer.gains")
        defaults.set(-4.5, forKey: "equalizer.preamp")
        let parameters = EqualizerParameters()
        let settings = EqualizerSettings(defaults: defaults, parameters: parameters)
        #expect(settings.gains == saved.map(Float.init))
        #expect(settings.preamp == -4.5)
        #expect(settings.preset == nil)
        #expect(settings.isEnabled)
        #expect(parameters.snapshot.gainsDB[0] == 4.5)
        #expect(parameters.snapshot.preampDB == -4.5)
    }

    @MainActor
    @Test func savedPresetsAndOutOfRangeValuesLoadSafely() throws {
        let defaults = try #require(UserDefaults(suiteName: "EqualizerTests.\(UUID())"))
        defaults.set(EqualizerPreset.rock.rawValue, forKey: "equalizer.preset")
        defaults.set(EqualizerPreset.rock.gains.map(Double.init), forKey: "equalizer.gains")
        #expect(EqualizerSettings(defaults: defaults, parameters: EqualizerParameters()).preset == .rock)

        defaults.removeObject(forKey: "equalizer.preset")
        defaults.set([30, -30, 0, 0, 0, 0, 0, 0, 0, 0] as [Double], forKey: "equalizer.gains")
        defaults.set(5.0, forKey: "equalizer.preamp")
        let clamped = EqualizerSettings(defaults: defaults, parameters: EqualizerParameters())
        #expect(clamped.gains[0] == 12)
        #expect(clamped.gains[1] == -12)
        #expect(clamped.preamp == 0)
    }

    @MainActor
    @Test func profilesRememberTheirNameUntilABandMoves() throws {
        let defaults = try #require(UserDefaults(suiteName: "EqualizerTests.\(UUID())"))
        let settings = EqualizerSettings(defaults: defaults, parameters: EqualizerParameters())
        settings.apply(gains: [6.9, 3.3, -1.1, -1.6, 0.6, -0.8, 0.1, -1, 3.9, -6.5], preamp: -7.5, profileName: "Sennheiser HD 600")
        #expect(settings.profileName == "Sennheiser HD 600")
        #expect(settings.preset == nil)
        #expect(EqualizerSettings(defaults: defaults, parameters: EqualizerParameters()).profileName == "Sennheiser HD 600")
        settings.setGain(1, band: 4)
        #expect(settings.profileName == nil)
        #expect(EqualizerSettings(defaults: defaults, parameters: EqualizerParameters()).profileName == nil)
    }
}
