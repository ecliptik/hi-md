import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio // UnsafeMutableAudioBufferListPointer on the Mac
#endif
import Foundation
import Synchronization

/// Whether the audio taps limit peaks, readable from the render thread without a lock.
nonisolated final class LimiterParameters: Sendable {
    static let shared = LimiterParameters()

    private let enabledValue = Atomic<Bool>(true)

    var isEnabled: Bool {
        get { enabledValue.load(ordering: .relaxed) }
        set { enabledValue.store(newValue, ordering: .relaxed) }
    }
}

/// A lookahead-free peak limiter for one audio tap. ReplayGain, its preamp and the equalizer can
/// push peaks past full scale; this holds them at `ceiling`.
///
/// The gain drops at once to whatever the loudest channel of a frame needs (no attack time, so no
/// sample ever passes the ceiling) and recovers exponentially afterwards. Channels share one gain,
/// so the stereo image doesn't move. Without lookahead the onset of a limited peak is a hard
/// gain step; at the few dB of overshoot loudness levelling produces this is far less audible than
/// clipping, and it adds no latency, which keeps gapless hand-offs and crossfades sample-aligned.
/// Everything is plain stored state: `process` never allocates, locks or logs.
nonisolated final class PeakLimiter: @unchecked Sendable {
    /// -1 dBFS leaves room for the inter-sample peaks of lossy decoders.
    static let ceiling: Float = 0.891
    static let releaseSeconds: Float = 0.08

    private let parameters: LimiterParameters
    private var channels = 2
    private var interleaved = false
    private var releaseCoefficient: Float = 0
    /// The gain applied to the previous frame, 1 when nothing is being limited.
    private(set) var gain: Float = 1

    init(parameters: LimiterParameters = .shared) {
        self.parameters = parameters
        prepare(sampleRate: 44100, channels: 2, interleaved: false)
    }

    /// Called from the tap's prepare callback with the processing format.
    func prepare(sampleRate: Double, channels: Int, interleaved: Bool) {
        let rate = Float(sampleRate > 0 ? sampleRate : 44100)
        self.channels = max(1, channels)
        self.interleaved = interleaved
        releaseCoefficient = 1 - exp(-1 / (Self.releaseSeconds * rate))
        gain = 1
    }

    /// Limits 32-bit float samples in place.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard parameters.isEnabled, frames > 0 else {
            gain = 1
            return
        }
        if interleaved {
            guard let data = buffers.first?.mData else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                let base = frame * channels
                var peak: Float = 0
                for channel in 0..<channels { peak = max(peak, abs(samples[base + channel])) }
                let g = nextGain(peak: peak)
                if g != 1 { for channel in 0..<channels { samples[base + channel] *= g } }
            }
        } else {
            let count = min(buffers.count, channels)
            for frame in 0..<frames {
                var peak: Float = 0
                for channel in 0..<count {
                    guard let data = buffers[channel].mData else { continue }
                    peak = max(peak, abs(data.assumingMemoryBound(to: Float.self)[frame]))
                }
                let g = nextGain(peak: peak)
                guard g != 1 else { continue }
                for channel in 0..<count {
                    guard let data = buffers[channel].mData else { continue }
                    data.assumingMemoryBound(to: Float.self)[frame] *= g
                }
            }
        }
    }

    /// The gain for a frame whose loudest sample is `peak`: instant attack, exponential release.
    @inline(__always)
    func nextGain(peak: Float) -> Float {
        let target = peak > Self.ceiling ? Self.ceiling / peak : 1
        if target < gain {
            gain = target
        } else {
            gain += (target - gain) * releaseCoefficient
            // Snap home (within 0.01 dB) so an idle limiter leaves samples bit-identical. Float
            // steps this small would otherwise stall just short of 1.
            if target == 1, gain > 0.999 { gain = 1 }
        }
        return gain
    }
}
