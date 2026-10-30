import Foundation
import SwiftSonic

/// A way to group the library's songs for the Library tiles.
nonisolated enum LibraryFacetKind: String, Hashable, Sendable {
    /// Genre tags, including every genre of multi-genre songs.
    case genre
    /// Artists credited on songs, including featured artists, as opposed to album artists.
    case trackArtist
    /// Composer credits.
    case composer
}

/// One genre, track artist or composer and how many songs it has.
nonisolated struct LibraryFacet: Hashable, Sendable, Identifiable {
    let kind: LibraryFacetKind
    /// The server's artist ID when there is one, otherwise the lowercased name; for genres, the
    /// spelling-insensitive `GenreName.key`, so "Trip-Hop" and "Trip Hop" are one genre.
    let key: String
    let name: String
    let songCount: Int
    /// True when `key` is a server artist ID that can open an artist page.
    let hasArtistID: Bool

    var id: String { kind.rawValue + ":" + key }
}

/// Builds genre, track-artist and composer lists from the local library index, so they work
/// offline and cost the server nothing.
nonisolated enum LibraryFacets {
    private static let pageSize = 2000

    /// The facet values one song belongs to, as (key, name, hasArtistID).
    static func values(of song: Song, kind: LibraryFacetKind) -> [(key: String, name: String, hasArtistID: Bool)] {
        switch kind {
        case .genre:
            let names = (song.genres ?? []).map(\.name) + [song.genre].compactMap { $0 }
            return unique(names.map { name in
                let key = GenreName.key(name)
                return (key: key.isEmpty ? name.lowercased() : key, name: name, hasArtistID: false)
            })
        case .trackArtist:
            if let artists = song.artists, !artists.isEmpty {
                return unique(artists.map { (key: $0.id, name: $0.name, hasArtistID: true) })
            }
            guard let name = song.artist else { return [] }
            if let id = song.artistId { return [(key: id, name: name, hasArtistID: true)] }
            return [(key: name.lowercased(), name: name, hasArtistID: false)]
        case .composer:
            let credited = (song.contributors ?? []).filter { $0.role.caseInsensitiveCompare("composer") == .orderedSame }
            if !credited.isEmpty {
                return unique(credited.map { (key: $0.artist.id, name: $0.artist.name, hasArtistID: true) })
            }
            guard let name = song.displayComposer else { return [] }
            return [(key: name.lowercased(), name: name, hasArtistID: false)]
        }
    }

    /// Facets sorted by name, with their song counts. A facet spelled several ways is shown
    /// under its most common spelling.
    static func facets(_ kind: LibraryFacetKind, in songs: [Song]) -> [LibraryFacet] {
        var counts: [String: (count: Int, hasArtistID: Bool, spellings: [String: Int])] = [:]
        for song in songs {
            for value in values(of: song, kind: kind) where !value.name.trimmingCharacters(in: .whitespaces).isEmpty {
                counts[value.key, default: (0, value.hasArtistID, [:])].count += 1
                counts[value.key]?.spellings[value.name, default: 0] += 1
            }
        }
        return counts.map { key, entry in
            let name = entry.spellings.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? key
            return LibraryFacet(kind: kind, key: key, name: name, songCount: entry.count, hasArtistID: entry.hasArtistID)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func songs(of facet: LibraryFacet, in songs: [Song]) -> [Song] {
        songs.filter { song in values(of: song, kind: facet.kind).contains { $0.key == facet.key } }
    }

    @concurrent
    static func load(_ kind: LibraryFacetKind, store: LibraryIndexStore, serverID: UUID) async throws -> [LibraryFacet] {
        facets(kind, in: try await allSongs(store: store, serverID: serverID))
    }

    @concurrent
    static func songs(of facet: LibraryFacet, store: LibraryIndexStore, serverID: UUID) async throws -> [Song] {
        songs(of: facet, in: try await allSongs(store: store, serverID: serverID))
            .sorted { ($0.album ?? "", $0.discNumber ?? 0, $0.track ?? 0) < ($1.album ?? "", $1.discNumber ?? 0, $1.track ?? 0) }
    }

    /// Every song in the index, read a page at a time.
    static func allSongs(store: LibraryIndexStore, serverID: UUID) async throws -> [Song] {
        var songs: [Song] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await store.songs(serverID: serverID, offset: offset, count: pageSize)
            songs += page
            guard page.count == pageSize else { return songs }
            offset += pageSize
        }
    }

    private static func unique(_ values: [(key: String, name: String, hasArtistID: Bool)]) -> [(key: String, name: String, hasArtistID: Bool)] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.key).inserted }
    }
}
