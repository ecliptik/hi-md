import Accelerate
import AVFoundation
#if canImport(CoreAudio)
import CoreAudio // UnsafeMutableAudioBufferListPointer on the Mac
#endif
import Darwin
import Foundation
import Synchronization

/// A read-only copy of what each deck's audio tap plays, for Winamp mode's visualiser.
///
/// Each deck owns one `VisualizerSampleRing`, allocated with the deck, and its tap copies post-EQ
/// samples into it only while a visualiser is attached. The render thread never allocates, locks
/// or waits, and nothing here changes how the decks are scheduled.
nonisolated final class VisualizerTap: Sendable {
    static let shared = VisualizerTap()
    /// Posted when the first visualiser attaches or the last one detaches. The engine then
    /// installs taps on the loaded items, as it does when the equalizer is turned on.
    static let attachmentDidChange = Notification.Name("VisualizerTap.attachmentDidChange")
    /// Rings written longer ago than this are treated as silent: a paused or idle deck.
    static let staleAfter: TimeInterval = 0.25

    private let attachments = Atomic<Int>(0)
    private let rings = Mutex<[WeakRing]>([])

    private struct WeakRing: Sendable {
        weak var ring: VisualizerSampleRing?
    }

    init() {}

    var isAttached: Bool { attachments.load(ordering: .relaxed) > 0 }

    /// Called when a deck is created, never on the render thread.
    func makeRing() -> VisualizerSampleRing {
        let ring = VisualizerSampleRing(tap: self)
        rings.withLock { rings in
            rings.removeAll { $0.ring == nil }
            rings.append(WeakRing(ring: ring))
        }
        return ring
    }

    /// Attachments are counted, so two visualisers can share the tap.
    func attach() {
        if attachments.add(1, ordering: .relaxed).newValue == 1 {
            NotificationCenter.default.post(name: Self.attachmentDidChange, object: self)
        }
    }

    func detach() {
        let result = attachments.subtract(1, ordering: .relaxed).newValue
        if result < 0 {
            attachments.store(0, ordering: .relaxed)
        } else if result == 0 {
            NotificationCenter.default.post(name: Self.attachmentDidChange, object: self)
        }
    }

    /// Mixes the newest `output.count` samples of every recently written ring into `output`.
    /// During a crossfade both decks contribute, before their deck volumes. Returns the sample
    /// rate of the loudest contributor, or nil when every deck is idle.
    func readMix(into output: UnsafeMutableBufferPointer<Float>,
                 scratch: UnsafeMutableBufferPointer<Float>,
                 now: UInt64 = mach_absolute_time()) -> Double? {
        guard let base = output.baseAddress, let scratchBase = scratch.baseAddress, scratch.count >= output.count else {
            return nil
        }
        output.update(repeating: 0)
        let live = rings.withLock { $0.compactMap(\.ring) }
        var sampleRate: Double?
        for ring in live where ring.isFresh(now: now) {
            guard ring.readLatest(into: UnsafeMutableBufferPointer(start: scratchBase, count: output.count)) else { continue }
            vDSP_vadd(base, 1, scratchBase, 1, base, 1, vDSP_Length(output.count))
            sampleRate = sampleRate ?? ring.sampleRate
        }
        return sampleRate
    }
}

/// A lock-free ring of mono samples with one writer, the deck's render thread, and one reader,
/// the visualiser's analysis queue. Memory is allocated once, when the deck is created.
nonisolated final class VisualizerSampleRing: @unchecked Sendable {
    /// A power of two, several times larger than any tap buffer, so the reader's window is never
    /// overwritten while it copies.
    static let capacity = 16_384
    private static let mask = capacity - 1
    private static let maxFramesPerWrite = capacity / 4

    private let tap: VisualizerTap
    private let samples: UnsafeMutablePointer<Float>
    /// Total frames written. Released after the samples, so a reader that acquires it sees them.
    private let written = Atomic<Int>(0)
    private let writing = Atomic<Bool>(false)
    private let lastWriteTime = Atomic<UInt64>(0)
    private let sampleRateBits = Atomic<UInt64>(Double(44_100).bitPattern)

    fileprivate init(tap: VisualizerTap) {
        self.tap = tap
        samples = .allocate(capacity: Self.capacity)
        samples.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        samples.deallocate()
    }

    /// Set from the tap's prepare callback.
    var sampleRate: Double {
        get { Double(bitPattern: sampleRateBits.load(ordering: .relaxed)) }
        set { sampleRateBits.store((newValue > 0 ? newValue : 44_100).bitPattern, ordering: .relaxed) }
    }

    /// Render thread. Downmixes 32-bit float tap audio, interleaved or not, and returns at once
    /// when no visualiser is attached.
    func write(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard tap.isAttached, frames > 0, !buffers.isEmpty else { return }
        // A second writer (an old item's tap still finishing) drops its buffer instead of waiting.
        guard !writing.exchange(true, ordering: .acquiring) else { return }
        defer { writing.store(false, ordering: .releasing) }

        let count = min(frames, Self.maxFramesPerWrite)
        let start = written.load(ordering: .relaxed)
        if buffers.count == 1, buffers[0].mNumberChannels > 1 {
            guard let data = buffers[0].mData else { return }
            let channels = Int(buffers[0].mNumberChannels)
            let source = data.assumingMemoryBound(to: Float.self)
            let scale = 1 / Float(channels)
            for frame in 0..<count {
                var sum: Float = 0
                for channel in 0..<channels { sum += source[frame * channels + channel] }
                samples[(start + frame) & Self.mask] = sum * scale
            }
        } else {
            let scale = 1 / Float(buffers.count)
            for (index, buffer) in buffers.enumerated() {
                guard let data = buffer.mData else { continue }
                let source = data.assumingMemoryBound(to: Float.self)
                for frame in 0..<count {
                    let slot = (start + frame) & Self.mask
                    let value = source[frame] * scale
                    samples[slot] = index == 0 ? value : samples[slot] + value
                }
            }
        }
        lastWriteTime.store(mach_absolute_time(), ordering: .relaxed)
        written.store(start + count, ordering: .releasing)
    }

    /// Writes mono samples directly. Used by tests and by sources that aren't audio taps.
    func write(mono source: UnsafeBufferPointer<Float>) {
        guard tap.isAttached, let base = source.baseAddress else { return }
        guard !writing.exchange(true, ordering: .acquiring) else { return }
        defer { writing.store(false, ordering: .releasing) }
        let count = min(source.count, Self.maxFramesPerWrite)
        let start = written.load(ordering: .relaxed)
        for frame in 0..<count { samples[(start + frame) & Self.mask] = base[frame] }
        lastWriteTime.store(mach_absolute_time(), ordering: .relaxed)
        written.store(start + count, ordering: .releasing)
    }

    /// Copies the newest `output.count` samples, oldest first, padding with silence before the
    /// first write. Returns false if the writer lapped the copy, which leaves `output` unusable.
    func readLatest(into output: UnsafeMutableBufferPointer<Float>) -> Bool {
        let count = min(output.count, Self.capacity - Self.maxFramesPerWrite)
        guard count > 0, let base = output.baseAddress else { return false }
        let end = written.load(ordering: .acquiring)
        let start = end - count
        for index in 0..<count {
            let position = start + index
            base[index] = position < 0 ? 0 : samples[position & Self.mask]
        }
        let after = written.load(ordering: .acquiring)
        return after - start <= Self.capacity - Self.maxFramesPerWrite
    }

    func isFresh(now: UInt64) -> Bool {
        let last = lastWriteTime.load(ordering: .relaxed)
        guard last > 0, now >= last else { return last > 0 }
        return Self.seconds(fromHostTicks: now - last) <= VisualizerTap.staleAfter
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func seconds(fromHostTicks ticks: UInt64) -> TimeInterval {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }
}
