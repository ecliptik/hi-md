import AVFoundation
import Foundation
import Testing
@testable import Minidisc

@Suite("Waveform envelope for the Mac MiniPlayer's scrubber")
struct WaveformEnvelopeTests {
    /// One second at amplitude 0.2, one second at 0.8, then half a second of silence.
    private static func writeTestTone(to url: URL, settings: [String: Any]) throws {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(sampleRate * 2.5)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                let time = Double(frame) / sampleRate
                let amplitude: Double = time < 1 ? 0.2 : (time < 2 ? 0.8 : 0)
                samples[frame] = Float(amplitude * sin(2 * .pi * 440 * time))
            }
        }
        try file.write(from: buffer)
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "WaveformTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func mean(_ levels: ArraySlice<Float>) -> Float {
        levels.reduce(0, +) / Float(levels.count)
    }

    @Test func binsKeepTheLoudestBlockAndNormalise() {
        let bins = WaveformEnvelope.bins(fromBlockLevels: [0.1, 0.4, 0.2, 0.8], count: 2)
        #expect(bins.count == 2)
        #expect(abs(bins[0] - (0.4 / 0.8 as Float).squareRoot()) < 0.0001)
        #expect(bins[1] == 1)
        // More bins than blocks still gives the bins asked for.
        #expect(WaveformEnvelope.bins(fromBlockLevels: [0.5, 1], count: 6).count == 6)
        // Silence and nothing stay flat at zero.
        #expect(WaveformEnvelope.bins(fromBlockLevels: [0, 0, 0], count: 4) == [0, 0, 0, 0])
        #expect(WaveformEnvelope.bins(fromBlockLevels: [], count: 3) == [0, 0, 0])
    }

    @Test func encodingRoundTripsWithinAByte() {
        let envelope = WaveformEnvelope(levels: [0, 0.25, 0.5, 1])
        let decoded = WaveformEnvelope(encoded: envelope.encoded)
        #expect(envelope.encoded.count == 4)
        for (original, restored) in zip(envelope.levels, decoded?.levels ?? []) {
            #expect(abs(original - restored) <= 1 / 255)
        }
        #expect(WaveformEnvelope(encoded: Data()) == nil)
    }

    @Test(arguments: ["wav", "m4a"])
    func readsTheShapeOfAGeneratedTone(fileExtension: String) async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "tone.\(fileExtension)")
        let settings: [String: Any] = fileExtension == "wav"
            ? [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false]
            : [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
               AVEncoderBitRateKey: 128_000]
        try Self.writeTestTone(to: url, settings: settings)

        let envelope = try await WaveformEnvelope.read(from: url, binCount: 250)
        let levels = envelope.levels
        #expect(levels.count == 250)
        #expect(levels.allSatisfy { (0...1).contains($0) })
        // 100 bins a second. The loud second is the reference; the quiet one is a quarter of
        // its amplitude, so the square root puts it near a half.
        let quiet = Self.mean(levels[10..<90])
        let loud = Self.mean(levels[110..<190])
        let silent = Self.mean(levels[215..<250])
        #expect(abs(loud - 1) < 0.08, "loud \(loud)")
        #expect(abs(quiet - 0.5) < 0.1, "quiet \(quiet)")
        #expect(silent < 0.06, "silent \(silent)")
    }

    @Test func aFileThatIsNotAudioThrows() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "not-audio.mp3")
        try Data("hello".utf8).write(to: url)
        await #expect(throws: (any Error).self) {
            _ = try await WaveformEnvelope.read(from: url)
        }
    }

    @Test func theStoreMeasuresOnceAndKeepsTheResultOnDisk() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appending(path: "tone.wav")
        try Self.writeTestTone(to: audio, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100,
                                                     AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16])
        let cacheDirectory = directory.appending(path: "Waveforms")
        let store = WaveformStore(directory: cacheDirectory)
        #expect(await store.cached(forKey: "server-song") == nil)
        let first = await store.envelope(forKey: "server-song", audioFile: audio)
        #expect(first?.levels.count == WaveformEnvelope.defaultBinCount)

        // A new store (the next launch) reads it from disk without the audio file.
        try FileManager.default.removeItem(at: audio)
        let relaunched = WaveformStore(directory: cacheDirectory)
        let restored = await relaunched.cached(forKey: "server-song")
        #expect(restored != nil)
        #expect(restored?.levels.count == first?.levels.count)
        // A song whose file can't be read has no waveform.
        #expect(await relaunched.envelope(forKey: "other", audioFile: audio) == nil)
    }
}
