import Foundation

/// How a stream-cache copy was fetched, so a lower-quality copy never replaces a better one and
/// playback can tell whether a copy is good enough for the current network's stream quality.
nonisolated enum CachedAudioQuality: Hashable, Sendable, Comparable {
    /// A server transcode at this bitrate (0 when the server picked the bitrate).
    case lossy(kbps: Int)
    /// Cached before qualities were recorded. Cellular caching was off by default then, so these
    /// copies are almost always Wi-Fi originals: they satisfy any stream quality, and only an
    /// original replaces them.
    case unrecorded
    /// The file exactly as stored on the server.
    case original

    /// The quality the Subsonic `stream` parameters ask for.
    init(subsonicFormat format: String?, maxBitRate: Int?) {
        let bitrate = maxBitRate ?? 0
        if format?.lowercased() == "raw" || (format == nil && bitrate <= 0) {
            self = .original
        } else {
            self = .lossy(kbps: max(0, bitrate))
        }
    }

    /// The quality a Subsonic `stream` URL asks for, read from its `format` and `maxBitRate`.
    init(streamURL: URL) {
        let items = URLComponents(url: streamURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let format = items.first { $0.name == "format" }?.value
        let bitrate = items.first { $0.name == "maxBitRate" }?.value.flatMap(Int.init)
        self.init(subsonicFormat: format, maxBitRate: bitrate)
    }

    private var rank: Int {
        switch self {
        case .lossy(let kbps): min(kbps, Int.max - 2)
        case .unrecorded: Int.max - 1
        case .original: Int.max
        }
    }

    static func < (lhs: CachedAudioQuality, rhs: CachedAudioQuality) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Whether a new copy at `other` may replace a cached copy at this quality.
    func canBeReplaced(by other: CachedAudioQuality) -> Bool {
        other >= self
    }

    /// Whether a cached copy at this quality is as good as a stream at `streamQuality`.
    func satisfies(_ streamQuality: CachedAudioQuality) -> Bool {
        switch self {
        case .original, .unrecorded: true
        case .lossy: rank >= streamQuality.rank
        }
    }

    // MARK: - File name tag

    /// Stored in the cache file name, so no schema migration of the user store is needed.
    var fileNameTag: String {
        switch self {
        case .lossy(let kbps): "kbps\(kbps)"
        case .unrecorded: "unrecorded"
        case .original: "original"
        }
    }

    /// Reads the tag written by `taggedFileName`; names without one were cached earlier.
    init(fileName: String) {
        let stem = (fileName as NSString).deletingPathExtension
        guard let separator = stem.lastIndex(of: "~") else {
            self = .unrecorded
            return
        }
        let tag = stem[stem.index(after: separator)...]
        if tag == "original" {
            self = .original
        } else if tag.hasPrefix("kbps"), let kbps = Int(tag.dropFirst(4)) {
            self = .lossy(kbps: kbps)
        } else {
            self = .unrecorded
        }
    }

    /// `<stem>~<tag>.<ext>`: the extension stays last because AVPlayer reads the container from it.
    func taggedFileName(stem: String, extension ext: String) -> String {
        "\(stem)~\(fileNameTag).\(ext)"
    }
}

/// A complete stream-cache copy and the quality it was fetched at.
nonisolated struct CachedAudioEntry: Sendable, Equatable {
    let url: URL
    let quality: CachedAudioQuality
}
