import Accelerate
import Dispatch
import Foundation
import Synchronization

/// One visualiser frame: Winamp-style spectrum bars, an oscilloscope trace and a peak level.
nonisolated struct AudioAnalysisFrame: Sendable, Equatable {
    /// 0...1 per band, low to high frequency.
    var spectrum: [Float]
    /// -1...1 samples, oldest first.
    var waveform: [Float]
    /// Largest absolute sample in the window, 0...1.
    var peak: Float

    static func silent(bandCount: Int, waveformLength: Int) -> AudioAnalysisFrame {
        AudioAnalysisFrame(
            spectrum: Array(repeating: 0, count: bandCount),
            waveform: Array(repeating: 0, count: waveformLength),
            peak: 0
        )
    }
}

nonisolated struct AudioAnalyzerConfiguration: Sendable, Equatable {
    /// Bars across the spectrum. Winamp's main window draws 75; compact views use 19 or 20.
    var bandCount: Int
    /// Samples per FFT, a power of two.
    var fftSize: Int
    /// Points in the oscilloscope trace. Winamp's is 75 pixels wide.
    var waveformLength: Int
    /// The lowest and highest band edges in Hz. Bands are spaced logarithmically between them.
    var minimumFrequency: Float
    var maximumFrequency: Float
    /// Levels at or below this many dBFS draw as an empty bar.
    var floorDecibels: Float

    static let winamp = AudioAnalyzerConfiguration(
        bandCount: 75, fftSize: 2048, waveformLength: 75,
        minimumFrequency: 50, maximumFrequency: 16_000, floorDecibels: -70
    )

    static let compact = AudioAnalyzerConfiguration(
        bandCount: 19, fftSize: 1024, waveformLength: 38,
        minimumFrequency: 50, maximumFrequency: 16_000, floorDecibels: -70
    )
}

/// Turns a window of mono PCM into an `AudioAnalysisFrame` with a Hann-windowed vDSP FFT.
/// All buffers are allocated up front. An instance is not thread-safe: use it from one queue.
nonisolated final class PlaybackAudioAnalyzer: @unchecked Sendable {
    let configuration: AudioAnalyzerConfiguration

    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let windowed: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imaginary: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    /// Inclusive FFT bin range per band, rebuilt when the sample rate changes.
    private var bandBins: [ClosedRange<Int>] = []
    private var bandSampleRate: Double = 0

    init(configuration: AudioAnalyzerConfiguration = .winamp) {
        precondition(configuration.fftSize >= 64 && configuration.fftSize & (configuration.fftSize - 1) == 0,
                     "fftSize must be a power of two")
        precondition(configuration.bandCount > 0 && configuration.waveformLength > 0)
        self.configuration = configuration
        let size = configuration.fftSize
        log2n = vDSP_Length(log2(Double(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = .allocate(capacity: size)
        vDSP_hann_window(window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        windowed = .allocate(capacity: size)
        windowed.initialize(repeating: 0, count: size)
        real = .allocate(capacity: size / 2)
        real.initialize(repeating: 0, count: size / 2)
        imaginary = .allocate(capacity: size / 2)
        imaginary.initialize(repeating: 0, count: size / 2)
        magnitudes = .allocate(capacity: size / 2)
        magnitudes.initialize(repeating: 0, count: size / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        window.deallocate()
        windowed.deallocate()
        real.deallocate()
        imaginary.deallocate()
        magnitudes.deallocate()
    }

    /// Analyses the newest `fftSize` samples; shorter input is padded with leading silence.
    func analyze(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> AudioAnalysisFrame {
        let size = configuration.fftSize
        let half = size / 2
        let tail = samples.count > size ? UnsafeBufferPointer(rebasing: samples.suffix(size)) : samples
        let padding = size - tail.count
        windowed.update(repeating: 0, count: padding)
        if let base = tail.baseAddress {
            (windowed + padding).update(from: base, count: tail.count)
        }

        var peak: Float = 0
        vDSP_maxmgv(windowed, 1, &peak, vDSP_Length(size))
        let waveform = Self.waveform(UnsafeBufferPointer(start: windowed, count: size), length: configuration.waveformLength)

        vDSP_vmul(windowed, 1, window, 1, windowed, 1, vDSP_Length(size))
        var split = DSPSplitComplex(realp: real, imagp: imaginary)
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
        // zrip packs the Nyquist term into imagp[0]; the DC bin isn't drawn, so drop both.
        imaginary[0] = 0
        vDSP_zvabs(&split, 1, magnitudes, 1, vDSP_Length(half))
        // zrip doubles each bin and a Hann window halves a sine's energy: 2/N recovers amplitude.
        var scale = 2 / Float(size)
        vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, vDSP_Length(half))

        rebuildBandsIfNeeded(sampleRate: sampleRate)
        let floor = configuration.floorDecibels
        let spectrum = bandBins.map { bins -> Float in
            var amplitude: Float = 0
            vDSP_maxv(magnitudes + bins.lowerBound, 1, &amplitude, vDSP_Length(bins.count))
            let decibels = 20 * log10(max(amplitude, 1e-9))
            return min(max((decibels - floor) / -floor, 0), 1)
        }
        return AudioAnalysisFrame(spectrum: spectrum, waveform: waveform, peak: min(peak, 1))
    }

    func analyze(_ samples: [Float], sampleRate: Double) -> AudioAnalysisFrame {
        samples.withUnsafeBufferPointer { analyze($0, sampleRate: sampleRate) }
    }

    /// The band whose frequency range contains `frequency`, or nil outside the spectrum.
    func band(containing frequency: Float) -> Int? {
        let edges = Self.bandEdges(configuration)
        guard frequency >= edges[0], frequency < edges[edges.count - 1] else { return nil }
        return edges.indices.dropLast().last { edges[$0] <= frequency }
    }

    /// `bandCount + 1` logarithmically spaced edges, in Hz.
    static func bandEdges(_ configuration: AudioAnalyzerConfiguration) -> [Float] {
        let ratio = configuration.maximumFrequency / configuration.minimumFrequency
        return (0...configuration.bandCount).map {
            configuration.minimumFrequency * pow(ratio, Float($0) / Float(configuration.bandCount))
        }
    }

    private func rebuildBandsIfNeeded(sampleRate: Double) {
        let rate = sampleRate > 0 ? sampleRate : 44_100
        guard rate != bandSampleRate || bandBins.isEmpty else { return }
        bandSampleRate = rate
        let half = configuration.fftSize / 2
        let binWidth = Float(rate) / Float(configuration.fftSize)
        let edges = Self.bandEdges(configuration)
        bandBins = (0..<configuration.bandCount).map { band in
            // Narrow low bands share a bin, as Winamp's do.
            let low = min(max(Int((edges[band] / binWidth).rounded()), 1), half - 1)
            let high = min(max(Int((edges[band + 1] / binWidth).rounded()) - 1, low), half - 1)
            return low...high
        }
    }

    private static func waveform(_ samples: UnsafeBufferPointer<Float>, length: Int) -> [Float] {
        let step = Double(samples.count) / Double(length)
        return (0..<length).map { index in
            min(max(samples[min(Int(Double(index) * step), samples.count - 1)], -1), 1)
        }
    }
}

/// Publishes analysis frames at about 30 per second while started, reading the decks through
/// `VisualizerTap`. Start it only while a visualiser is on screen: starting attaches the tap.
nonisolated final class PlaybackVisualizer: @unchecked Sendable {
    static let framesPerSecond = 30

    let configuration: AudioAnalyzerConfiguration
    /// How far a bar may fall per frame, as Winamp's bars fall rather than drop.
    var barFalloff: Float = 0.08

    private let tap: VisualizerTap
    private let queue = DispatchQueue(label: "minidisc.visualizer", qos: .userInteractive)
    private let analyzer: PlaybackAudioAnalyzer
    private let published: Mutex<AudioAnalysisFrame>
    private let timer = Mutex<DispatchSourceTimer?>(nil)
    /// Analysis-queue state.
    private let input: UnsafeMutableBufferPointer<Float>
    private let scratch: UnsafeMutableBufferPointer<Float>
    private var bars: [Float]

    init(configuration: AudioAnalyzerConfiguration = .winamp, tap: VisualizerTap = .shared) {
        self.configuration = configuration
        self.tap = tap
        analyzer = PlaybackAudioAnalyzer(configuration: configuration)
        let silent = AudioAnalysisFrame.silent(bandCount: configuration.bandCount,
                                               waveformLength: configuration.waveformLength)
        published = Mutex(silent)
        bars = silent.spectrum
        input = .allocate(capacity: configuration.fftSize)
        input.initialize(repeating: 0)
        scratch = .allocate(capacity: configuration.fftSize)
        scratch.initialize(repeating: 0)
    }

    deinit {
        stop()
        input.deallocate()
        scratch.deallocate()
    }

    /// The newest frame. Safe from any thread; SwiftUI can read it from a 30 fps `TimelineView`.
    var latestFrame: AudioAnalysisFrame { published.withLock { $0 } }

    var isRunning: Bool { timer.withLock { $0 != nil } }

    func start() {
        let started = timer.withLock { timer -> Bool in
            guard timer == nil else { return false }
            let source = DispatchSource.makeTimerSource(queue: queue)
            let interval = DispatchTimeInterval.nanoseconds(1_000_000_000 / Self.framesPerSecond)
            source.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(5))
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
            return true
        }
        if started { tap.attach() }
    }

    func stop() {
        let stopped = timer.withLock { timer -> Bool in
            guard let source = timer else { return false }
            source.cancel()
            timer = nil
            return true
        }
        guard stopped else { return }
        tap.detach()
        let silent = AudioAnalysisFrame.silent(bandCount: configuration.bandCount,
                                               waveformLength: configuration.waveformLength)
        published.withLock { $0 = silent }
    }

    /// Runs one analysis pass now. The timer calls it; tests call it directly through `queue`.
    func tick() {
        let sampleRate = tap.readMix(into: input, scratch: scratch)
        var frame = analyzer.analyze(UnsafeBufferPointer(input), sampleRate: sampleRate ?? 44_100)
        for index in frame.spectrum.indices {
            bars[index] = max(frame.spectrum[index], bars[index] - barFalloff)
        }
        frame.spectrum = bars
        published.withLock { $0 = frame }
    }
}
