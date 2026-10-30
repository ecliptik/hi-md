import Foundation
import SwiftSonic

nonisolated struct HomeFavorites: Codable, Sendable {
    var songs: [Song] = []
    var albums: [AlbumID3] = []
    var artists: [ArtistID3] = []
}

nonisolated extension HomeFavorites {
    /// The server's starred items, newest favourite first. Servers promise no order for them, and
    /// Navidrome's changed from one refresh to the next, reshuffling Home's shelves.
    init(starred: Starred2, songLimit: Int = .max, albumLimit: Int = .max, artistLimit: Int = .max) {
        songs = Self.newestFirst(starred.song ?? [], starred: \.starred, id: \.id, limit: songLimit)
        albums = Self.newestFirst(starred.album ?? [], starred: \.starred, id: \.id, limit: albumLimit)
        artists = Self.newestFirst(starred.artist ?? [], starred: \.starred, id: \.id, limit: artistLimit)
    }

    /// Most recently starred first; items with the same date (or none) keep a fixed order by ID.
    static func newestFirst<T>(_ items: [T], starred: KeyPath<T, Date?>, id: KeyPath<T, String>, limit: Int) -> [T] {
        Array(items.sorted { lhs, rhs in
            let left = lhs[keyPath: starred] ?? .distantPast, right = rhs[keyPath: starred] ?? .distantPast
            return left != right ? left > right : lhs[keyPath: id] < rhs[keyPath: id]
        }.prefix(limit))
    }
}

enum HomePersonalization {
    /// How recently an album must have been played to count as in heavy rotation.
    nonisolated static let heavyRotationWindow: TimeInterval = 45 * 24 * 60 * 60

    /// Albums played a lot that have also been played lately, most plays first. The server's
    /// most-played list ranks by plays ever, so an old favourite led it long after the listener
    /// moved on. Servers that don't report when an album was last played get that list as it is.
    nonisolated static func heavyRotation(_ mostPlayed: [AlbumID3], excluding ids: Set<String>, now: Date = .now,
                                          limit: Int = 12) -> [AlbumID3] {
        let candidates = unique(mostPlayed, excluding: ids)
        guard candidates.contains(where: { $0.played != nil }) else { return Array(candidates.prefix(limit)) }
        let recent = candidates.enumerated().filter { _, album in
            album.played.map { now.timeIntervalSince($0) <= heavyRotationWindow } ?? false
        }
        return recent
            .sorted { lhs, rhs in
                let left = lhs.element.playCount ?? 0, right = rhs.element.playCount ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element)
    }

    nonisolated static func unique(_ albums: [AlbumID3], excluding ids: Set<String> = []) -> [AlbumID3] {
        var seen = ids
        return albums.filter { seen.insert($0.id).inserted }
    }

    /// Genre shelves that each show different albums. Servers list a genre's albums by name, and
    /// an album tagged with several genres (electronic, ambient, experimental) topped every one
    /// of those shelves alike. Albums keep to the first shelf that has them, each shelf is
    /// shuffled by `seed` so the same artist's catalogue doesn't open every row, genres differing
    /// only in spelling count once, and a shelf left with fewer than `minimum` albums is dropped.
    nonisolated static func distinctGenreShelves(_ fetched: [(name: String, albums: [AlbumID3])], limit: Int = 5,
                                     perShelf: Int = 20, minimum: Int = 6, seed: String) -> [(name: String, albums: [AlbumID3])] {
        var shelves: [(name: String, albums: [AlbumID3])] = []
        var seenAlbums = Set<String>()
        var seenGenres = Set<String>()
        for (name, albums) in fetched where shelves.count < limit {
            guard seenGenres.insert(GenreName.key(name)).inserted else { continue }
            let fresh = unique(albums, excluding: seenAlbums)
                .sorted { shuffleKey($0.id, seed) < shuffleKey($1.id, seed) }
                .prefix(perShelf)
            guard fresh.count >= minimum else { continue }
            seenAlbums.formUnion(fresh.map(\.id))
            shelves.append((name, Array(fresh)))
        }
        return shelves
    }

    /// A stable order for `id` under `seed` (FNV-1a), so a shelf keeps its order until the seed
    /// changes, unlike `hashValue`, which differs on every launch.
    nonisolated private static func shuffleKey(_ id: String, _ seed: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (seed + "|" + id).utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func rediscovery(favorites: [AlbumID3], frequent: [AlbumID3], recent: [AlbumID3]) -> [AlbumID3] {
        unique(favorites + frequent, excluding: Set(recent.map(\.id))).prefix(12).map { $0 }
    }

    static func relevantAdditions(_ additions: [AlbumID3], favorites: HomeFavorites, frequent: [AlbumID3]) -> [AlbumID3] {
        let ids = Set(favorites.artists.map(\.id) + favorites.albums.compactMap(\.artistId)
                      + favorites.songs.compactMap(\.artistId) + frequent.prefix(8).compactMap(\.artistId))
        // Names are a fallback only for servers that omit artist IDs.
        let names = Set((favorites.artists.map(\.name) + favorites.albums.compactMap(\.artist)
                         + favorites.songs.compactMap(\.artist) + frequent.prefix(8).compactMap(\.artist))
            .map(LibrarySearchRanking.normalized).filter { !$0.isEmpty })
        return unique(additions.filter { album in
            if let id = album.artistId { return ids.contains(id) }
            return album.artist.map { names.contains(LibrarySearchRanking.normalized($0)) } ?? false
        })
    }
}
