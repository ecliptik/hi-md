import AVFoundation
import Foundation
import Testing
@testable import Minidisc

private func sine(frequency: Double, amplitude: Float = 0.5, sampleRate: Double = 44_100, count: Int = 2048) -> [Float] {
    (0..<count).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate)) }
}

@Suite("Playback audio analyzer")
struct PlaybackAudioAnalyzerTests {
    @Test(arguments: [100.0, 440.0, 1_000.0, 3_000.0, 10_000.0])
    func sinePeaksInItsBand(frequency: Double) throws {
        let analyzer = PlaybackAudioAnalyzer(configuration: .winamp)
        let frame = analyzer.analyze(sine(frequency: frequency), sampleRate: 44_100)
        let expected = try #require(analyzer.band(containing: Float(frequency)))
        let loudest = try #require(frame.spectrum.indices.max { frame.spectrum[$0] < frame.spectrum[$1] })
        // Narrow low bands can share an FFT bin, so the loudest may be a neighbour with the same value.
        #expect(abs(loudest - expected) <= 1 || frame.spectrum[expected] == frame.spectrum[loudest])
        #expect(frame.spectrum[expected] > 0.85)
        // Bands two octaves away are near the floor.
        for band in frame.spectrum.indices {
            let edges = PlaybackAudioAnalyzer.bandEdges(analyzer.configuration)
            if edges[band + 1] < Float(frequency) / 4 || edges[band] > Float(frequency) * 4 {
                #expect(frame.spectrum[band] < 0.35, "band \(band) at \(edges[band]) Hz")
            }
        }
    }

    @Test func compactConfigurationAndOtherSampleRates() throws {
        let analyzer = PlaybackAudioAnalyzer(configuration: .compact)
        let frame = analyzer.analyze(sine(frequency: 5_000, sampleRate: 48_000, count: 1024), sampleRate: 48_000)
        #expect(frame.spectrum.count == 19)
        #expect(frame.waveform.count == 38)
        let loudest = frame.spectrum.indices.max { frame.spectrum[$0] < frame.spectrum[$1] }
        #expect(loudest == analyzer.band(containing: 5_000))
    }

    @Test func peakAndWaveformFollowTheSignal() {
        let analyzer = PlaybackAudioAnalyzer()
        let frame = analyzer.analyze(sine(frequency: 440, amplitude: 0.5), sampleRate: 44_100)
        #expect(abs(frame.peak - 0.5) < 0.01)
        #expect(frame.waveform.count == 75)
        #expect(frame.waveform.allSatisfy { abs($0) <= 0.5 + 1e-4 })
        #expect(frame.waveform.contains { $0 > 0.2 } && frame.waveform.contains { $0 < -0.2 })
    }

    @Test func silenceIsFlat() {
        let analyzer = PlaybackAudioAnalyzer()
        let frame = analyzer.analyze([Float](repeating: 0, count: 2048), sampleRate: 44_100)
        #expect(frame == .silent(bandCount: 75, waveformLength: 75))
    }

    @Test func shortInputIsPaddedAndClippingIsClamped() {
        let analyzer = PlaybackAudioAnalyzer()
        let frame = analyzer.analyze([Float](repeating: 2, count: 100), sampleRate: 44_100)
        #expect(frame.peak == 1)
        #expect(frame.waveform.allSatisfy { (-1...1).contains($0) })
        #expect(frame.spectrum.allSatisfy { (0...1).contains($0) })
    }

    @Test func bandsAreContiguousAndCoverTheRange() {
        let configuration = AudioAnalyzerConfiguration.winamp
        let edges = PlaybackAudioAnalyzer.bandEdges(configuration)
        #expect(edges.count == 76)
        #expect(abs(edges.first! - 50) < 0.01)
        #expect(abs(edges.last! - 16_000) < 1)
        #expect(zip(edges, edges.dropFirst()).allSatisfy { $0 < $1 })
        let analyzer = PlaybackAudioAnalyzer(configuration: configuration)
        #expect(analyzer.band(containing: 50) == 0)
        #expect(analyzer.band(containing: 15_999) == 74)
        #expect(analyzer.band(containing: 20) == nil)
        #expect(analyzer.band(containing: 20_000) == nil)
    }
}

// MARK: - Tap

/// Notifications are posted synchronously on the attaching thread.
private nonisolated final class NotificationCounter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite("Visualizer tap", .serialized)
struct VisualizerTapTests {
    /// A private tap, so these tests never attach the shared one the engine observes.
    private let tap = VisualizerTap()

    private func readMix(_ count: Int = 8) -> (samples: [Float], sampleRate: Double?) {
        var output = [Float](repeating: -1, count: count)
        var scratch = [Float](repeating: 0, count: count)
        let rate = output.withUnsafeMutableBufferPointer { out in
            scratch.withUnsafeMutableBufferPointer { tap.readMix(into: out, scratch: $0) }
        }
        return (output, rate)
    }

    @Test func writesAreIgnoredUntilAttached() {
        let ring = tap.makeRing()
        [Float](repeating: 0.5, count: 16).withUnsafeBufferPointer { ring.write(mono: $0) }
        let result = readMix()
        #expect(result.sampleRate == nil)
        #expect(result.samples == [Float](repeating: 0, count: 8))
    }

    @Test func attachmentIsCountedAndAnnounced() async {
        let notifications = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: VisualizerTap.attachmentDidChange, object: tap, queue: nil
        ) { _ in notifications.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }
        #expect(!tap.isAttached)
        tap.attach()
        tap.attach()
        #expect(tap.isAttached)
        tap.detach()
        #expect(tap.isAttached)
        tap.detach()
        #expect(!tap.isAttached)
        tap.detach()
        #expect(!tap.isAttached)
        #expect(notifications.value == 2)
        #expect(!VisualizerTap.shared.isAttached)
    }

    @Test func readsTheNewestSamplesOldestFirst() {
        tap.attach()
        defer { tap.detach() }
        let ring = tap.makeRing()
        ring.sampleRate = 48_000
        (0..<20).map(Float.init).withUnsafeBufferPointer { ring.write(mono: $0) }
        let result = readMix(4)
        #expect(result.samples == [16, 17, 18, 19])
        #expect(result.sampleRate == 48_000)
    }

    @Test func downmixesInterleavedAndPlanarTapBuffers() {
        tap.attach()
        defer { tap.detach() }
        let ring = tap.makeRing()

        // Interleaved stereo: one buffer, two channels. L = 1, R = 0 → 0.5.
        var interleaved: [Float] = [1, 0, 1, 0, 1, 0, 1, 0]
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        interleaved.withUnsafeMutableBytes { bytes in
            list.count = 1
            list[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
            ring.write(list, frames: 4)
        }
        #expect(readMix(4).samples == [0.5, 0.5, 0.5, 0.5])

        // Planar stereo: two buffers. L = 0.25, R = 0.75 → 0.5.
        var left: [Float] = [0.25, 0.25]
        var right: [Float] = [0.75, -0.75]
        left.withUnsafeMutableBytes { leftBytes in
            right.withUnsafeMutableBytes { rightBytes in
                list.count = 2
                list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(leftBytes.count), mData: leftBytes.baseAddress)
                list[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(rightBytes.count), mData: rightBytes.baseAddress)
                ring.write(list, frames: 2)
            }
        }
        #expect(readMix(2).samples == [0.5, -0.25])
    }

    @Test func crossfadingDecksAreMixed() {
        tap.attach()
        defer { tap.detach() }
        let outgoing = tap.makeRing()
        let incoming = tap.makeRing()
        [Float](repeating: 0.25, count: 8).withUnsafeBufferPointer { outgoing.write(mono: $0) }
        [Float](repeating: 0.5, count: 8).withUnsafeBufferPointer { incoming.write(mono: $0) }
        #expect(readMix(4).samples == [0.75, 0.75, 0.75, 0.75])
    }

    @Test func idleDecksGoSilent() {
        tap.attach()
        defer { tap.detach() }
        let ring = tap.makeRing()
        [Float](repeating: 0.5, count: 8).withUnsafeBufferPointer { ring.write(mono: $0) }
        var output = [Float](repeating: 0, count: 4)
        var scratch = [Float](repeating: 0, count: 4)
        let later = mach_absolute_time() + UInt64(2 * hostTicksPerSecond())
        let rate = output.withUnsafeMutableBufferPointer { out in
            scratch.withUnsafeMutableBufferPointer { tap.readMix(into: out, scratch: $0, now: later) }
        }
        #expect(rate == nil)
        #expect(output == [0, 0, 0, 0])
    }

    @Test func anAttachedVisualiserRequiresTheEngineTap() {
        #expect(AVPlayerEngine.requiresAudioTap(linearGain: 0.5, equalizerEnabled: false, visualizerAttached: true))
        #expect(!AVPlayerEngine.requiresAudioTap(linearGain: 0.5, equalizerEnabled: false, visualizerAttached: false))
    }

    private func hostTicksPerSecond() -> Double {
        1 / VisualizerSampleRing.seconds(fromHostTicks: 1)
    }
}

@Suite("Playback visualizer", .serialized)
struct PlaybackVisualizerTests {
    @Test func startAttachesAndStopDetaches() {
        let tap = VisualizerTap()
        let visualizer = PlaybackVisualizer(configuration: .compact, tap: tap)
        visualizer.start()
        visualizer.start()
        #expect(tap.isAttached)
        #expect(visualizer.isRunning)
        visualizer.stop()
        #expect(!tap.isAttached)
        #expect(!visualizer.isRunning)
        #expect(visualizer.latestFrame == .silent(bandCount: 19, waveformLength: 38))
    }

    @Test func tickPublishesTheDeckSpectrumAndBarsFallGradually() throws {
        let tap = VisualizerTap()
        tap.attach()
        defer { tap.detach() }
        let ring = tap.makeRing()
        ring.sampleRate = 44_100
        let visualizer = PlaybackVisualizer(configuration: .winamp, tap: tap)
        sine(frequency: 1_000).withUnsafeBufferPointer { ring.write(mono: $0) }
        visualizer.tick()
        let frame = visualizer.latestFrame
        let band = try #require(PlaybackAudioAnalyzer(configuration: .winamp).band(containing: 1_000))
        #expect(frame.spectrum[band] > 0.85)
        #expect(abs(frame.peak - 0.5) < 0.01)

        // Silence: the bar drops by the falloff rather than to zero.
        [Float](repeating: 0, count: 4096).withUnsafeBufferPointer { ring.write(mono: $0) }
        visualizer.tick()
        let next = visualizer.latestFrame.spectrum[band]
        #expect(abs(next - (frame.spectrum[band] - visualizer.barFalloff)) < 0.001)
        #expect(visualizer.latestFrame.peak == 0)
    }
}
