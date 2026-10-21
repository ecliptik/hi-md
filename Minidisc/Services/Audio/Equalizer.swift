import AVFoundation
import Foundation
import Synchronization

// MARK: - Bands and presets

nonisolated enum Equalizer {
    /// Ten octave-spaced bands, as in most music players.
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = 10
    static let gainRange: ClosedRange<Float> = -12...12
    /// Roughly one octave wide, so neighbouring bands blend smoothly.
    static let q: Float = 1.41
}

nonisolated enum EqualizerPreset: String, CaseIterable, Identifiable, Sendable {
    case flat, bassBoost, bassReducer, trebleBoost, trebleReducer, vocal, loudness
    case rock, pop, jazz, classical, electronic, hipHop, acoustic, lateNight

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .flat: "Flat"
        case .bassBoost: "Bass Booster"
        case .bassReducer: "Bass Reducer"
        case .trebleBoost: "Treble Booster"
        case .trebleReducer: "Treble Reducer"
        case .vocal: "Vocal Booster"
        case .loudness: "Loudness"
        case .rock: "Rock"
        case .pop: "Pop"
        case .jazz: "Jazz"
        case .classical: "Classical"
        case .electronic: "Electronic"
        case .hipHop: "Hip-Hop"
        case .acoustic: "Acoustic"
        case .lateNight: "Late Night"
        }
    }

    /// Gains in dB for the ten bands, 32 Hz to 16 kHz.
    var gains: [Float] {
        switch self {
        case .flat: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .bassBoost: [6, 5, 4, 2.5, 1, 0, 0, 0, 0, 0]
        case .bassReducer: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0]
        case .trebleBoost: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]
        case .trebleReducer: [0, 0, 0, 0, 0, -1, -2.5, -4, -5, -6]
        case .vocal: [-2, -2, -1, 1, 3, 4, 3, 2, 0, -1]
        case .loudness: [5, 4, 2, 0, -1, 0, -1, 1, 4, 5]
        case .rock: [4, 3, 2, 0.5, -1, -0.5, 1, 2.5, 3.5, 4]
        case .pop: [-1, 0, 1.5, 3, 4, 3, 1.5, 0, -0.5, -1]
        case .jazz: [3, 2, 1, 2, -1.5, -1.5, 0, 1.5, 2.5, 3]
        case .classical: [4, 3, 2.5, 1.5, -1, -1, 0, 2, 3, 3.5]
        case .electronic: [4.5, 4, 1.5, 0, -2, 1.5, 1, 1.5, 4, 4.5]
        case .hipHop: [5, 4, 1.5, 3, -1, -1, 1.5, -0.5, 2, 3]
        case .acoustic: [4, 3.5, 3, 1.5, 2, 2, 3, 3, 2.5, 1.5]
        case .lateNight: [-3, -2, -1, 0, 1, 2, 2, 1, 0, -2]
        }
    }

    /// Headroom so the strongest boost doesn't clip: the negative of the largest gain.
    var preamp: Float { -max(0, gains.max() ?? 0) }
}

// MARK: - Shared parameters

/// What the settings screen chose, readable from the audio render thread. The render thread
/// checks `generation` on every buffer, which is lock-free; it takes the lock only to read a new
/// snapshot after a change.
nonisolated final class EqualizerParameters: Sendable {
    struct Snapshot: Sendable, Equatable {
        var isEnabled = false
        var preampDB: Float = 0
        /// Ten band gains in dB; SIMD storage keeps snapshot copies allocation-free.
        var gainsDB = SIMD16<Float>(repeating: 0)

        /// Whether processing changes the sound at all.
        var isAudible: Bool {
            isEnabled && (preampDB != 0 || (0..<Equalizer.bandCount).contains { gainsDB[$0] != 0 })
        }
    }

    static let shared = EqualizerParameters()
    static let didChange = Notification.Name("minidisc.equalizerDidChange")

    private let state = Mutex(Snapshot())
    private let generationValue = Atomic<UInt64>(1)

    var generation: UInt64 { generationValue.load(ordering: .acquiring) }
    var snapshot: Snapshot { state.withLock { $0 } }
    var isEnabled: Bool { snapshot.isEnabled }

    func update(_ snapshot: Snapshot) {
        let changed = state.withLock { current -> Bool in
            guard current != snapshot else { return false }
            current = snapshot
            return true
        }
        guard changed else { return }
        generationValue.add(1, ordering: .releasing)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

// MARK: - Processing

/// Ten peaking biquad filters for one audio tap. All memory is allocated in `prepare`, which
/// runs before rendering starts, so `process` never allocates or blocks on the render thread.
nonisolated final class EqualizerProcessor: @unchecked Sendable {
    static let maxChannels = 8
    private static let coefficientsPerBand = 5
    private static let statePerFilter = 4

    private let parameters: EqualizerParameters
    private var sampleRate: Float = 44100
    private var channels = 2
    private var interleaved = false
    private var seenGeneration: UInt64 = 0
    private var active = false
    private var preampLinear: Float = 1
    private var bandCount = 0
    /// b0, b1, b2, a1, a2 per active band, normalised by a0.
    private let coefficients: UnsafeMutablePointer<Float>
    /// x1, x2, y1, y2 per band per channel.
    private let state: UnsafeMutablePointer<Float>

    init(parameters: EqualizerParameters = .shared) {
        self.parameters = parameters
        coefficients = .allocate(capacity: Equalizer.bandCount * Self.coefficientsPerBand)
        coefficients.initialize(repeating: 0, count: Equalizer.bandCount * Self.coefficientsPerBand)
        state = .allocate(capacity: Self.maxChannels * Equalizer.bandCount * Self.statePerFilter)
        state.initialize(repeating: 0, count: Self.maxChannels * Equalizer.bandCount * Self.statePerFilter)
    }

    deinit {
        coefficients.deallocate()
        state.deallocate()
    }

    /// Called from the tap's prepare callback with the processing format.
    func prepare(sampleRate: Double, channels: Int, interleaved: Bool) {
        self.sampleRate = Float(sampleRate > 0 ? sampleRate : 44100)
        self.channels = max(1, min(channels, Self.maxChannels))
        self.interleaved = interleaved
        seenGeneration = 0
        reset()
    }

    func reset() {
        state.update(repeating: 0, count: Self.maxChannels * Equalizer.bandCount * Self.statePerFilter)
    }

    /// Re-reads the settings when they have changed. Returns whether processing is needed.
    @discardableResult
    func refreshIfNeeded() -> Bool {
        let generation = parameters.generation
        guard generation != seenGeneration else { return active }
        seenGeneration = generation
        let snapshot = parameters.snapshot
        let wasActive = active
        active = snapshot.isAudible
        guard active else { return false }
        if !wasActive { reset() }
        preampLinear = pow(10, snapshot.preampDB / 20)
        // Bands at or above ~0.45 of the sample rate can't be represented; leave them out.
        bandCount = 0
        for band in 0..<Equalizer.bandCount where Equalizer.frequencies[band] < sampleRate * 0.45 {
            let c = Self.peakingCoefficients(frequency: Equalizer.frequencies[band], gainDB: snapshot.gainsDB[band],
                                             q: Equalizer.q, sampleRate: sampleRate)
            let base = coefficients + bandCount * Self.coefficientsPerBand
            base[0] = c.b0; base[1] = c.b1; base[2] = c.b2; base[3] = c.a1; base[4] = c.a2
            bandCount += 1
        }
        return true
    }

    /// Filters 32-bit float samples in place. `buffers` are the tap's audio buffers.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard refreshIfNeeded() else { return }
        if interleaved {
            guard let data = buffers.first?.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            for channel in 0..<channels {
                filter(samples + channel, stride: channels, frames: frames, channel: channel)
            }
        } else {
            for (channel, buffer) in buffers.enumerated() where channel < Self.maxChannels {
                guard let data = buffer.mData else { continue }
                filter(data.assumingMemoryBound(to: Float.self), stride: 1, frames: frames, channel: channel)
            }
        }
    }

    private func filter(_ samples: UnsafeMutablePointer<Float>, stride: Int, frames: Int, channel: Int) {
        let channelState = state + channel * Equalizer.bandCount * Self.statePerFilter
        for frame in 0..<frames {
            var x = samples[frame * stride] * preampLinear
            for band in 0..<bandCount {
                let c = coefficients + band * Self.coefficientsPerBand
                let s = channelState + band * Self.statePerFilter
                let y = c[0] * x + c[1] * s[0] + c[2] * s[1] - c[3] * s[2] - c[4] * s[3]
                s[1] = s[0]; s[0] = x
                s[3] = s[2]; s[2] = y
                x = y
            }
            samples[frame * stride] = x
        }
    }

    /// RBJ Audio EQ Cookbook peaking filter, normalised so a0 = 1.
    static func peakingCoefficients(frequency: Float, gainDB: Float, q: Float, sampleRate: Float)
        -> (b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Float.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)
        let a0 = 1 + alpha / a
        return ((1 + alpha * a) / a0, (-2 * cosW0) / a0, (1 - alpha * a) / a0, (-2 * cosW0) / a0, (1 - alpha / a) / a0)
    }
}
