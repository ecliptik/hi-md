import Accelerate
import AVFoundation
import Foundation
import OSLog

/// A song's loudness over its length, drawn by the Mac MiniPlayer's waveform scrubber: `levels`
/// from 0 to 1, evenly spaced from the start of the song to its end. It's read once from a
/// downloaded or cached file and kept by `WaveformStore`.
nonisolated struct WaveformEnvelope: Equatable, Sendable {
    let levels: [Float]

    /// Enough bars for a 300-point scrubber without bars thinner than a point and a half.
    static let defaultBinCount = 200
    /// Frames summed into one loudness reading before the readings are binned.
    static let framesPerBlock = 1024

    init(levels: [Float]) {
        self.levels = levels
    }

    // MARK: Binning

    /// `count` bins from per-block RMS loudness. Each bin keeps the loudest block in its span, so
    /// a short hit isn't averaged away; the loudest bin becomes 1, and a square root lifts quiet
    /// passages so they stay visible beside loud ones.
    static func bins(fromBlockLevels blocks: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !blocks.isEmpty else { return Array(repeating: 0, count: count) }
        var bins = [Float](repeating: 0, count: count)
        for bin in 0..<count {
            let start = bin * blocks.count / count
            let end = max((bin + 1) * blocks.count / count, start + 1)
            bins[bin] = blocks[start..<min(end, blocks.count)].max() ?? 0
        }
        let loudest = bins.max() ?? 0
        guard loudest > 0 else { return bins }
        return bins.map { ($0 / loudest).squareRoot() }
    }

    // MARK: Reading a file

    enum ReadError: Error {
        case noAudioTrack
        case unreadable
    }

    /// Decodes the file at `url` to PCM and measures it. It runs off the main actor and checks
    /// for cancellation between buffers, so a skipped song stops costing time.
    @concurrent
    static func read(from url: URL, binCount: Int = defaultBinCount) async throws -> WaveformEnvelope {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ReadError.noAudioTrack }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw ReadError.unreadable }
        let provider = reader.outputProvider(for: output)
        try reader.start()
        defer { if reader.status == .reading { reader.cancelReading() } }

        var meter = BlockMeter()
        while let ready = try await provider.next() {
            try Task.checkCancellation()
            ready.withUnsafeSampleBuffer { buffer in meter.add(buffer) }
        }
        guard reader.status == .completed else { throw reader.error ?? ReadError.unreadable }
        return WaveformEnvelope(levels: bins(fromBlockLevels: meter.finish(), count: binCount))
    }

    /// RMS loudness per `framesPerBlock` frames, carried across sample buffers.
    private struct BlockMeter {
        private var blocks: [Float] = []
        private var sumOfSquares: Float = 0
        private var samplesInBlock = 0
        private var samples: [Float] = []

        mutating func finish() -> [Float] {
            if samplesInBlock > 0 {
                blocks.append((sumOfSquares / Float(samplesInBlock)).squareRoot())
                sumOfSquares = 0
                samplesInBlock = 0
            }
            return blocks
        }

        mutating func add(_ buffer: CMSampleBuffer) {
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  let data = CMSampleBufferGetDataBuffer(buffer) else { return }
            let channels = max(Int(description.mChannelsPerFrame), 1)
            let blockSamples = WaveformEnvelope.framesPerBlock * channels
            let count = CMBlockBufferGetDataLength(data) / MemoryLayout<Float>.size
            guard count > 0 else { return }
            if samples.count < count { samples = [Float](repeating: 0, count: count) }
            let status = samples.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { return }

            var sum = sumOfSquares
            var filled = samplesInBlock
            var finished: [Float] = []
            samples.withUnsafeBufferPointer { pointer in
                var offset = 0
                while offset < count {
                    let take = min(blockSamples - filled, count - offset)
                    var partial: Float = 0
                    vDSP_svesq(pointer.baseAddress! + offset, 1, &partial, vDSP_Length(take))
                    sum += partial
                    filled += take
                    offset += take
                    if filled == blockSamples {
                        finished.append((sum / Float(blockSamples)).squareRoot())
                        sum = 0
                        filled = 0
                    }
                }
            }
            blocks += finished
            sumOfSquares = sum
            samplesInBlock = filled
        }
    }

    // MARK: Storage

    /// One byte per level: a 200-bar waveform is 200 bytes on disk.
    var encoded: Data {
        Data(levels.map { UInt8((min(max($0, 0), 1) * 255).rounded()) })
    }

    init?(encoded data: Data) {
        guard !data.isEmpty else { return nil }
        levels = data.map { Float($0) / 255 }
    }
}

/// Waveforms by song, read once and kept in memory and in the Caches folder, so the scrubber
/// draws a song's waveform straight away the next time it plays.
actor WaveformStore {
    private let directory: URL
    private var memory: [String: WaveformEnvelope] = [:]
    private var recent: [String] = []
    private var reading: [String: Task<WaveformEnvelope?, Never>] = [:]
    private static let memoryLimit = 64

    init(directory: URL) {
        self.directory = directory
    }

    /// The store under Caches/Waveforms.
    static func inCaches() -> WaveformStore {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return WaveformStore(directory: caches.appending(path: "Waveforms", directoryHint: .isDirectory))
    }

    /// The waveform already measured for `key`, from memory or disk.
    func cached(forKey key: String) -> WaveformEnvelope? {
        if let envelope = memory[key] { return envelope }
        guard let url = fileURL(forKey: key),
              let data = try? Data(contentsOf: url),
              let envelope = WaveformEnvelope(encoded: data) else { return nil }
        remember(envelope, forKey: key)
        return envelope
    }

    /// The waveform for `key`, measuring `audioFile` if it hasn't been yet. Two callers asking
    /// for the same song share one reading. Nil when the file can't be decoded.
    func envelope(forKey key: String, audioFile: URL) async -> WaveformEnvelope? {
        if let envelope = cached(forKey: key) { return envelope }
        if let task = reading[key] { return await task.value }
        let task = Task<WaveformEnvelope?, Never> {
            do {
                return try await WaveformEnvelope.read(from: audioFile)
            } catch {
                if !(error is CancellationError) {
                    Logger.player.debug("Waveform: couldn't read \(audioFile.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                return nil
            }
        }
        reading[key] = task
        let envelope = await task.value
        reading[key] = nil
        if let envelope {
            remember(envelope, forKey: key)
            save(envelope, forKey: key)
        }
        return envelope
    }

    private func remember(_ envelope: WaveformEnvelope, forKey key: String) {
        memory[key] = envelope
        recent.removeAll { $0 == key }
        recent.append(key)
        while recent.count > Self.memoryLimit {
            memory[recent.removeFirst()] = nil
        }
    }

    private func save(_ envelope: WaveformEnvelope, forKey key: String) {
        guard let url = fileURL(forKey: key) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? envelope.encoded.write(to: url, options: .atomic)
    }

    private func fileURL(forKey key: String) -> URL? {
        SafeFileName.url(forRelativePath: SafeFileName.forID(key) + ".waveform", in: directory)
    }
}
