import CoreGraphics
import Foundation
import SwiftSonic
import UIKit
@testable import Minidisc

/// Deterministic, realistic-looking library data for the benchmarks and the equivalence tests:
/// repeated words, shared prefixes, accents and punctuation, so every ranking tier is exercised.
nonisolated enum PerformanceFixtures {
    static let words = [
        "Love", "Night", "the", "Blue", "Fire", "Café", "Björk", "Señor", "Dream", "River", "Stone", "Heart",
        "Light", "Dance", "Summer", "Rain", "City", "Golden", "Shadow", "Echo", "Wild", "Sky", "Ocean",
        "Midnight", "Road", "Home", "Silver", "Storm", "Moon", "Sun", "Lovely", "Nightfall", "Bluebird",
        "Jóga", "Ænima", "Rock'n'Roll", "Part II", "(Live)", "Remix", "of", "and", "Ångström", "Déjà Vu",
    ]

    /// A linear congruential generator, so every run sees the same library.
    struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        mutating func phrase(_ count: ClosedRange<Int>) -> String {
            let length = count.lowerBound + next(count.count)
            return (0..<length).map { _ in words[next(words.count)] }.joined(separator: " ")
        }
    }

    static func songs(_ count: Int, artists: Int = 300, albums: Int = 600, seed: UInt64 = 1) -> [DisplayableSong] {
        var generator = Generator(state: seed)
        let artistNames = (0..<artists).map { _ in generator.phrase(1...2) }
        let albumNames = (0..<albums).map { _ in generator.phrase(1...3) }
        return (0..<count).map { index in
            let album = generator.next(albums)
            let artist = album % artists
            return DisplayableSong(
                id: "song-\(index)", title: generator.phrase(1...4), artist: artistNames[artist],
                albumId: "album-\(album)", albumName: albumNames[album], artistId: "artist-\(artist)",
                genre: nil, duration: 180, trackNumber: index % 12 + 1, isDownloaded: true,
                coverArtId: "al-\(album)", audioFormat: "FLAC", replayGainTrackGain: nil, replayGainTrackPeak: nil,
                replayGainAlbumGain: nil, replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
            )
        }
    }

    static func playlists(_ count: Int, seed: UInt64 = 7) -> [Playlist] {
        var generator = Generator(state: seed)
        return (0..<count).map { index in
            Playlist(id: "playlist-\(index)", name: generator.phrase(1...3), songCount: 20, duration: 3600,
                     comment: index.isMultiple(of: 3) ? generator.phrase(2...5) : nil)
        }
    }

    /// About 5,000 searchable items: 4,000 songs, the albums and artists they form, and 100 playlists.
    static func offlineSnapshot(songs count: Int = 4_000) -> OfflineBrowsingSnapshot {
        let songs = songs(count)
        let playlists = playlists(100)
        let membership = Dictionary(uniqueKeysWithValues: playlists.enumerated().map { index, playlist in
            (playlist.id, (0..<20).map { songs[(index * 37 + $0 * 11) % songs.count].id })
        })
        return OfflineBrowsingSnapshot(songs: songs, playlists: playlists, membership: membership)
    }

    /// A server answer with `artists + albums + songs` results, decoded like the real one.
    static func searchResult(artists: Int, albums: Int, songs: Int, seed: UInt64 = 3) throws -> SearchResult3 {
        var generator = Generator(state: seed)
        func quoted(_ text: String) -> String {
            String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        }
        let artistJSON = (0..<artists).map { index in
            "{\"id\":\"ar-\(index)\",\"name\":\(quoted(generator.phrase(1...2))),\"albumCount\":\(index % 5)}"
        }
        let albumJSON = (0..<albums).map { index in
            "{\"id\":\"al-\(index)\",\"name\":\(quoted(generator.phrase(1...3))),\"artist\":\(quoted(generator.phrase(1...2))),\"songCount\":10,\"duration\":2400}"
        }
        let songJSON = (0..<songs).map { index in
            "{\"id\":\"so-\(index % (songs - 5))\",\"title\":\(quoted(generator.phrase(1...4))),\"artist\":\(quoted(generator.phrase(1...2))),\"album\":\(quoted(generator.phrase(1...3))),\"isDir\":false}"
        }
        let json = "{\"artist\":[\(artistJSON.joined(separator: ","))],\"album\":[\(albumJSON.joined(separator: ","))],\"song\":[\(songJSON.joined(separator: ","))]}"
        return try JSONDecoder().decode(SearchResult3.self, from: Data(json.utf8))
    }

    // MARK: - Images

    /// An ordinary cover: a diagonal gradient with a few shapes, so neither signature matches early.
    static func cover(side: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let s = CGFloat(side)
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
            CGColor(srgbRed: 0.9, green: 0.4, blue: 0.1, alpha: 1), CGColor(srgbRed: 0.1, green: 0.2, blue: 0.6, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: s, y: s), options: [])
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.9, blue: 0.2, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: s * 0.2, y: s * 0.25, width: s * 0.3, height: s * 0.3))
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: s * 0.55, y: s * 0.6, width: s * 0.3, height: s * 0.1))
        return ctx.makeImage()!
    }

    /// Images that all point at one shared pixel buffer: each reports the full decoded size, as a real
    /// cover would, without the test allocating that memory once per image.
    static func sharedBufferImages(count: Int, side: Int) -> [UIImage] {
        let bytesPerRow = side * 4
        let data = Data(count: bytesPerRow * side) as CFData
        let provider = CGDataProvider(data: data)!
        return (0..<count).map { _ in
            let image = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
            return UIImage(cgImage: image)
        }
    }

    /// Decoded bytes the image holds, as the caches cost it.
    static func decodedBytes(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
