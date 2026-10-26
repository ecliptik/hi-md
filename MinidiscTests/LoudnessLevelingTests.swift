import AudioToolbox
import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio
#endif
import Foundation
import Testing
@testable import Minidisc

@Suite("Peak limiter")
struct PeakLimiterTests {
    private func limiter(enabled: Bool = true) -> PeakLimiter {
        let parameters = LimiterParameters()
        parameters.isEnabled = enabled
        let limiter = PeakLimiter(parameters: parameters)
        limiter.prepare(sampleRate: 48000, channels: 2, interleaved: false)
        return limiter
    }

    @Test("Audio under the ceiling passes bit-identical")
    func quietAudioUntouched() {
        let buffers = TestBuffers(channels: 2, frames: 4800) { _, frame in 0.8 * sin(Float(frame) * 0.05) }
        let original = buffers.samples(0)
        limiter().process(buffers.list, frames: buffers.frames)
        #expect(buffers.samples(0) == original)
    }

    @Test("Peaks pushed past full scale never exceed the ceiling")
    func holdsCeiling() {
        // +6 dB of gain on a full-scale sine: peaks of 2.0.
        let buffers = TestBuffers(channels: 2, frames: 48000) { channel, frame in
            2.0 * sin(2 * Float.pi * 440 * Float(frame) / 48000 + Float(channel))
        }
        limiter().process(buffers.list, frames: buffers.frames)
        let peak = (0..<2).flatMap { buffers.samples($0) }.map(abs).max() ?? 0
        #expect(peak <= PeakLimiter.ceiling + 1e-6)
        #expect(peak > PeakLimiter.ceiling * 0.95)
    }

    @Test("Channels share one gain, so the stereo balance holds")
    func linkedChannels() {
        let buffers = TestBuffers(channels: 2, frames: 1) { channel, _ in channel == 0 ? 1.8 : 0.9 }
        limiter().process(buffers.list, frames: 1)
        #expect(abs(buffers.samples(0)[0] / buffers.samples(1)[0] - 2) < 1e-5)
    }

    @Test("Gain drops instantly and recovers over the release time")
    func attackAndRelease() {
        let limiter = limiter()
        let attack = limiter.nextGain(peak: 1.782)
        #expect(abs(attack - PeakLimiter.ceiling / 1.782) < 1e-6)
        // One release time constant later the gap to unity has shrunk to about 1/e.
        var gain = attack
        for _ in 0..<Int(PeakLimiter.releaseSeconds * 48000) { gain = limiter.nextGain(peak: 0) }
        let remaining = (1 - gain) / (1 - attack)
        #expect(abs(remaining - exp(-1)) < 0.01)
        // Eventually it lets go completely.
        for _ in 0..<48000 { gain = limiter.nextGain(peak: 0) }
        #expect(gain == 1)
    }

    @Test("Turned off, it leaves even clipping audio alone")
    func disabled() {
        let buffers = TestBuffers(channels: 2, frames: 10) { _, _ in 1.5 }
        limiter(enabled: false).process(buffers.list, frames: buffers.frames)
        #expect(buffers.samples(0).allSatisfy { $0 == 1.5 })
    }

    @Test("Interleaved buffers are limited per frame")
    func interleaved() {
        let frames = 4
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)
        defer { samples.deallocate() }
        for index in 0..<(frames * 2) { samples[index] = index.isMultiple(of: 2) ? 1.5 : -0.5 }
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(list.unsafeMutablePointer) }
        list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(frames * 8), mData: samples)
        let parameters = LimiterParameters()
        let limiter = PeakLimiter(parameters: parameters)
        limiter.prepare(sampleRate: 48000, channels: 2, interleaved: true)
        limiter.process(list, frames: frames)
        for frame in 0..<frames {
            #expect(abs(samples[frame * 2]) <= PeakLimiter.ceiling + 1e-6)
            #expect(abs(samples[frame * 2] / samples[frame * 2 + 1] + 3) < 1e-5)
        }
    }
}

@Suite("ReplayGain with the limiter")
struct ReplayGainLimiterTests {
    private func gain(limiter: Bool, preAmp: Double, trackGain: Double, peak: Double?) -> Float {
        var song = DisplayableSong(
            id: "1", title: "T", artist: nil, albumId: nil, albumName: nil, artistId: nil, genre: nil,
            duration: 1, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: trackGain, replayGainTrackPeak: peak, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
        song.bitRate = nil
        return ReplayGainService.gainDB(
            track: song,
            config: ReplayGainConfig(enabled: true, mode: .track, preAmp: preAmp, limiter: limiter)
        )
    }

    @Test("With the limiter on, the preamp is applied in full and the limiter handles the peaks")
    func limiterAllowsFullPreamp() {
        // -18 LUFS reference: a track tagged -6 dB with a +4 dB preamp plays at -2 dB.
        #expect(abs(gain(limiter: true, preAmp: 4, trackGain: -6, peak: 1.0) - (-2)) < 0.001)
        #expect(abs(gain(limiter: true, preAmp: 4, trackGain: 3, peak: 0.9) - 7) < 0.001)
    }

    @Test("With the limiter off, gain stops where the track's peak would clip")
    func noLimiterCapsAtPeak() {
        let capped = gain(limiter: false, preAmp: 4, trackGain: 3, peak: 0.9)
        #expect(abs(capped - Float(-20 * log10(0.9))) < 0.001)
        // Quieter results are untouched.
        #expect(abs(gain(limiter: false, preAmp: 4, trackGain: -6, peak: 1.0) - (-2)) < 0.001)
    }

    @Test("The preamp is stored in whole decibels within ±15 dB")
    func preampSteps() {
        #expect(ReplayGainSettings.normalizedPreAmp(2.5) == 3)
        #expect(ReplayGainSettings.normalizedPreAmp(-2.5) == -3)
        #expect(ReplayGainSettings.normalizedPreAmp(-1.2) == -1)
        #expect(ReplayGainSettings.normalizedPreAmp(40) == 15)
        #expect(ReplayGainSettings.normalizedPreAmp(-40) == -15)
        #expect(ReplayGainSettings.normalizedPreAmp(.nan) == 0)
    }

    @MainActor
    @Test("The limiter defaults on, replaces Prevent Clipping and reaches the audio taps")
    func limiterSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: "limiter.\(UUID())"))
        defaults.set(false, forKey: "minidisc.replayGain.preventClipping")
        defaults.set(2.5, forKey: "minidisc.replayGain.preAmp")
        let parameters = LimiterParameters()
        parameters.isEnabled = false
        let settings = ReplayGainSettings(defaults: defaults, limiterParameters: parameters)
        #expect(settings.limiter)
        #expect(parameters.isEnabled)
        #expect(settings.preAmp == 3)
        #expect(defaults.object(forKey: "minidisc.replayGain.preventClipping") == nil)
        settings.limiter = false
        #expect(!parameters.isEnabled)
    }
}
