import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Stream quality decisions")
struct StreamQualityPolicyTests {
    private func policy(_ threshold: StreamThreshold, _ conversion: ConversionBitrate = .kbps128,
                        codec: ConversionCodec = .opus) -> StreamQualityPolicy {
        StreamQualityPolicy(threshold: threshold, conversion: conversion, codec: codec)
    }

    nonisolated private static let opus128 = StreamRequest(format: "opus", maxBitRate: 128)

    nonisolated struct Row: Sendable, CustomTestStringConvertible {
        let threshold: StreamThreshold
        let suffix: String?
        let bitRate: Int?
        let expected: StreamRequest
        var testDescription: String { "\(threshold) \(suffix ?? "?") \(bitRate.map(String.init) ?? "?")" }
    }

    nonisolated static let table: [Row] = [
        // Maximum never converts a playable file, whatever its size.
        Row(threshold: .maximum, suffix: "flac", bitRate: 4600, expected: .original),
        Row(threshold: .maximum, suffix: "mp3", bitRate: nil, expected: .original),
        // Above the threshold converts; at or below it streams the original.
        Row(threshold: .kbps320, suffix: "flac", bitRate: 900, expected: opus128),
        Row(threshold: .kbps320, suffix: "mp3", bitRate: 320, expected: .original),
        Row(threshold: .kbps320, suffix: "m4a", bitRate: 256, expected: .original),
        Row(threshold: .mbps1, suffix: "flac", bitRate: 1411, expected: opus128),
        Row(threshold: .mbps1, suffix: "flac", bitRate: 850, expected: .original),
        Row(threshold: .mbps2, suffix: "flac", bitRate: 4600, expected: opus128),
        Row(threshold: .kbps128, suffix: "mp3", bitRate: 192, expected: opus128),
        // A file no larger than the conversion would be is never converted.
        Row(threshold: .kbps128, suffix: "mp3", bitRate: 128, expected: .original),
        // Formats AVFoundation can't play convert even at Maximum.
        Row(threshold: .maximum, suffix: "wma", bitRate: 128, expected: opus128),
        Row(threshold: .maximum, suffix: "ogg", bitRate: 160, expected: opus128),
        Row(threshold: .maximum, suffix: "wv", bitRate: 900, expected: opus128),
        Row(threshold: .maximum, suffix: "dsf", bitRate: 5600, expected: opus128),
        Row(threshold: .maximum, suffix: "APE", bitRate: 700, expected: opus128),
        // Ogg Opus plays here, so an Opus original stays as it is.
        Row(threshold: .maximum, suffix: "opus", bitRate: 96, expected: .original),
        // An unknown bitrate converts under a limit and stays original without one.
        Row(threshold: .kbps320, suffix: "flac", bitRate: nil, expected: opus128),
        Row(threshold: .kbps320, suffix: nil, bitRate: 0, expected: opus128),
        Row(threshold: .maximum, suffix: nil, bitRate: nil, expected: .original),
    ]

    @Test("Threshold decision table", arguments: table)
    func decision(row: Row) {
        let traits = StreamSourceTraits(suffix: row.suffix, bitRate: row.bitRate)
        #expect(policy(row.threshold).request(for: traits, opusPlayable: true) == row.expected)
    }

    @Test("Missing metadata is treated like an unknown bitrate")
    func missingTraits() {
        #expect(policy(.maximum).request(for: nil, opusPlayable: true) == .original)
        #expect(policy(.kbps256).request(for: nil, opusPlayable: true) == Self.opus128)
    }

    @Test("Conversion uses the chosen bitrate and codec")
    func conversionTarget() {
        let traits = StreamSourceTraits(suffix: "flac", bitRate: 1000)
        #expect(policy(.kbps320, .kbps192).request(for: traits, opusPlayable: true) == StreamRequest(format: "opus", maxBitRate: 192))
        #expect(policy(.kbps320, .kbps64, codec: .aac).request(for: traits, opusPlayable: false) == StreamRequest(format: "aac", maxBitRate: 64))
    }

    @Test("Without Ogg Opus, Opus originals convert to the fallback codec")
    func opusOriginalWithoutOpusSupport() {
        let traits = StreamSourceTraits(suffix: "opus", bitRate: 96)
        #expect(policy(.maximum, codec: .aac).request(for: traits, opusPlayable: false) == StreamRequest(format: "aac", maxBitRate: 128))
    }

    @Test("Codec preference: Opus, then AAC, then MP3")
    func codecPreference() {
        #expect(ConversionCodec.preferred(isPlayable: { _ in true }) == .opus)
        #expect(ConversionCodec.preferred(isPlayable: { $0 == "audio/aac" }) == .aac)
        #expect(ConversionCodec.preferred(isPlayable: { _ in false }) == .mp3)
    }

    @Test("This OS plays Navidrome's Ogg Opus conversions")
    func deviceCodec() {
        #expect(ConversionCodec.preferred == .opus)
    }

    @Test("Song metadata becomes stream traits")
    func songTraits() {
        var song = DisplayableSong(
            id: "1", title: "T", artist: nil, albumId: nil, albumName: nil, artistId: nil, genre: nil,
            duration: 1, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: "FLAC",
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
        song.bitRate = 912
        song.channelCount = 2
        #expect(song.streamTraits == StreamSourceTraits(suffix: "flac", bitRate: 912, channelCount: 2))
    }
}

@Suite("Stream URL building")
struct StreamURLBuildingTests {
    private let client = SwiftSonicClient(
        configuration: ServerConfiguration(serverURL: URL(string: "https://music.example.com")!, username: "u", password: "p")
    )

    private func query(_ url: URL?) -> [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    @Test("Originals ask for format=raw without a bitrate cap")
    func original() {
        let q = query(MediaResolver.streamURL(client: client, songId: "song-1", request: .original))
        #expect(q["id"] == "song-1")
        #expect(q["format"] == "raw")
        #expect(q["maxBitRate"] == nil)
        #expect(q["estimateContentLength"] == "true")
    }

    @Test("Conversions name the codec and bitrate", arguments: ConversionCodec.allCases)
    func converted(codec: ConversionCodec) {
        let url = MediaResolver.streamURL(client: client, songId: "song-1", request: .converted(to: codec, at: .kbps160))
        let q = query(url)
        #expect(q["format"] == codec.rawValue)
        #expect(q["maxBitRate"] == "160")
        #expect(url?.path.hasSuffix("/rest/stream") == true || url?.path.hasSuffix("/rest/stream.view") == true)
    }
}

@Suite("Cached audio quality")
struct CachedAudioQualityTests {
    @Test("A stream URL names the quality it asked for")
    func fromStreamURL() throws {
        let raw = try #require(URL(string: "https://m.example/rest/stream?id=1&format=raw&estimateContentLength=false"))
        let opus = try #require(URL(string: "https://m.example/rest/stream?id=1&maxBitRate=128&format=opus"))
        let unspecified = try #require(URL(string: "https://m.example/rest/stream?id=1"))
        #expect(CachedAudioQuality(streamURL: raw) == .original)
        #expect(CachedAudioQuality(streamURL: opus) == .converted(format: "opus", kbps: 128))
        #expect(CachedAudioQuality(streamURL: unspecified) == .unknown)
    }

    @Test("The quality round-trips through the entry's MIME type")
    func roundTrip() {
        for quality in [CachedAudioQuality.original, .converted(format: "opus", kbps: 128), .converted(format: "mp3", kbps: nil)] {
            let tagged = quality.tagging("audio/ogg")
            #expect(CachedAudioQuality(mimeType: tagged) == quality)
            #expect(CachedAudioQuality.baseType(of: tagged) == "audio/ogg")
        }
        #expect(CachedAudioQuality.converted(format: "opus", kbps: 128).tagging("audio/ogg") == "audio/ogg; minidisc-quality=opus-128")
    }

    @Test("Entries cached before tagging read as unknown, and retagging replaces the old tag")
    func legacyAndRetag() {
        #expect(CachedAudioQuality(mimeType: "audio/mpeg") == .unknown)
        #expect(CachedAudioQuality(mimeType: "audio/ogg; codecs=opus") == .unknown)
        let retagged = CachedAudioQuality.original.tagging("audio/flac; minidisc-quality=mp3-192")
        #expect(retagged == "audio/flac; minidisc-quality=original")
    }
}
