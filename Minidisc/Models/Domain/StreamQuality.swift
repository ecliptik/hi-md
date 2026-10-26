import AVFoundation
import Foundation

/// Music above this bitrate is converted before it streams. Chosen separately for Wi-Fi and cellular.
nonisolated enum StreamThreshold: String, CaseIterable, Identifiable, Sendable {
    /// Never convert, unless the engine can't play the format.
    case maximum
    case mbps2
    case mbps1
    case kbps320
    case kbps256
    case kbps192
    case kbps160
    case kbps128

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .maximum: "Maximum"
        case .mbps2: "\(2) Mbps"
        case .mbps1: "\(1) Mbps"
        case .kbps320, .kbps256, .kbps192, .kbps160, .kbps128: "\(kbps ?? 0) kbps"
        }
    }

    /// The bitrate limit in kbps; nil for Maximum.
    var kbps: Int? {
        switch self {
        case .maximum: nil
        case .mbps2: 2000
        case .mbps1: 1000
        case .kbps320: 320
        case .kbps256: 256
        case .kbps192: 192
        case .kbps160: 160
        case .kbps128: 128
        }
    }
}

/// The bitrate a converted song is streamed at.
nonisolated enum ConversionBitrate: Int, CaseIterable, Identifiable, Sendable {
    case kbps256 = 256
    case kbps192 = 192
    case kbps160 = 160
    case kbps128 = 128
    case kbps96 = 96
    case kbps64 = 64

    var id: Int { rawValue }
    var kbps: Int { rawValue }
    var title: LocalizedStringResource { "\(kbps) kbps" }

    static let recommended: ConversionBitrate = .kbps128
}

/// The codec the server converts to. Not a user setting: it is the best one this device plays
/// gaplessly. Navidrome's default Opus transcoding writes Ogg Opus; AVFoundation trims its
/// pre-skip and end padding sample-exactly and seeks in it, so a converted album stays gapless.
/// ADTS AAC carries no priming information and leaves a short gap, so it is only the fallback
/// where Ogg Opus can't play.
nonisolated enum ConversionCodec: String, Sendable, CaseIterable {
    case opus
    case aac
    case mp3

    /// The Subsonic `format` value; Navidrome ships transcodings with these names.
    var subsonicFormat: String { rawValue }

    /// Codec names stay untranslated.
    var displayName: String {
        switch self {
        case .opus: "Opus"
        case .aac: "AAC"
        case .mp3: "MP3"
        }
    }

    static let preferred = ConversionCodec.preferred(isPlayable: AVURLAsset.isPlayableExtendedMIMEType)

    static func preferred(isPlayable: (String) -> Bool) -> ConversionCodec {
        if isPlayable("audio/ogg; codecs=opus") { return .opus }
        if isPlayable("audio/aac") { return .aac }
        return .mp3
    }
}

/// What the Subsonic metadata says about a song's original file.
nonisolated struct StreamSourceTraits: Sendable, Equatable {
    /// The file extension, such as `flac`.
    let suffix: String?
    /// The average bitrate in kbps.
    let bitRate: Int?
    let channelCount: Int?

    init(suffix: String?, bitRate: Int?, channelCount: Int? = nil) {
        self.suffix = suffix?.lowercased()
        self.bitRate = bitRate
        self.channelCount = channelCount
    }
}

/// The `format` and `maxBitRate` sent with a stream request.
nonisolated struct StreamRequest: Sendable, Equatable {
    let format: String
    let maxBitRate: Int?

    static let original = StreamRequest(format: rawFormat, maxBitRate: nil)
    static let rawFormat = "raw"

    static func converted(to codec: ConversionCodec, at bitrate: ConversionBitrate) -> StreamRequest {
        StreamRequest(format: codec.subsonicFormat, maxBitRate: bitrate.kbps)
    }

    var isOriginal: Bool { format == Self.rawFormat }
}

/// Decides, song by song, whether to stream the original file or ask the server to convert it.
nonisolated struct StreamQualityPolicy: Sendable, Equatable {
    let threshold: StreamThreshold
    let conversion: ConversionBitrate
    let codec: ConversionCodec

    /// File types AVFoundation plays directly. Anything else, such as Ogg Vorbis, WMA, WavPack,
    /// Monkey's Audio or DSD, is converted whatever the threshold. Opus counts only when the
    /// device plays Ogg Opus.
    static func canPlayOriginal(suffix: String, opusPlayable: Bool = ConversionCodec.preferred == .opus) -> Bool {
        if suffix == "opus" { return opusPlayable }
        return playableSuffixes.contains(suffix)
    }

    private static let playableSuffixes: Set<String> = [
        "mp3", "aac", "m4a", "m4b", "mp4", "alac", "flac", "wav", "wave",
        "aif", "aiff", "aifc", "caf", "ac3", "eac3",
    ]

    func request(for traits: StreamSourceTraits?) -> StreamRequest {
        request(for: traits, opusPlayable: codec == .opus)
    }

    func request(for traits: StreamSourceTraits?, opusPlayable: Bool) -> StreamRequest {
        let convert = StreamRequest.converted(to: codec, at: conversion)
        if let suffix = traits?.suffix, !suffix.isEmpty,
           !Self.canPlayOriginal(suffix: suffix, opusPlayable: opusPlayable) {
            return convert
        }
        guard let limit = threshold.kbps else { return .original }
        guard let bitRate = traits?.bitRate, bitRate > 0 else {
            // Without a bitrate the size is unknown; under a limit, converting is the safe side.
            return convert
        }
        // A conversion never helps a file that is already no larger than its result.
        guard bitRate > limit, bitRate > conversion.kbps else { return .original }
        return convert
    }
}

extension DisplayableSong {
    nonisolated var streamTraits: StreamSourceTraits {
        StreamSourceTraits(suffix: audioFormat, bitRate: bitRate, channelCount: channelCount)
    }
}

/// The quality a cached file was downloaded at, kept as a parameter on the cache entry's MIME
/// type so it needs no change to the stored model: `audio/ogg; minidisc-quality=opus-128`.
/// Entries cached before this existed read as `.unknown`.
nonisolated enum CachedAudioQuality: Sendable, Equatable {
    case original
    case converted(format: String, kbps: Int?)
    case unknown

    private static let parameter = "minidisc-quality"

    /// Reads the request a Subsonic stream URL made. A URL without `format` was served by the
    /// server's default for this client, so its quality is unknown.
    init(streamURL: URL) {
        let items = URLComponents(url: streamURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let format = items.first { $0.name == "format" }?.value?.lowercased()
        let maxBitRate = items.first { $0.name == "maxBitRate" }?.value.flatMap(Int.init)
        switch format {
        case nil, "": self = .unknown
        case StreamRequest.rawFormat: self = .original
        case let format?: self = .converted(format: format, kbps: maxBitRate.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    init(mimeType: String) {
        let parameters = mimeType.split(separator: ";").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        guard let value = parameters.first(where: { $0.hasPrefix(Self.parameter + "=") })?
            .dropFirst(Self.parameter.count + 1) else {
            self = .unknown
            return
        }
        if value == "original" {
            self = .original
            return
        }
        let parts = value.split(separator: "-", maxSplits: 1)
        guard let format = parts.first, !format.isEmpty else {
            self = .unknown
            return
        }
        self = .converted(format: String(format), kbps: parts.count > 1 ? Int(parts[1]) : nil)
    }

    /// `mimeType` with this quality attached, replacing any earlier tag.
    func tagging(_ mimeType: String) -> String {
        let base = Self.baseType(of: mimeType)
        switch self {
        case .unknown: return base
        case .original: return "\(base); \(Self.parameter)=original"
        case .converted(let format, let kbps):
            return "\(base); \(Self.parameter)=\(format)" + (kbps.map { "-\($0)" } ?? "")
        }
    }

    /// The MIME type without parameters, for code that switches on the type itself.
    static func baseType(of mimeType: String) -> String {
        String(mimeType.split(separator: ";", maxSplits: 1).first ?? "").trimmingCharacters(in: .whitespaces)
    }
}
