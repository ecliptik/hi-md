import Foundation
import SwiftSonic

enum LibrarySearchScope: String, CaseIterable, Identifiable, Hashable {
    case all, songs, albums, artists, playlists
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .all: "All"
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        }
    }
}

nonisolated enum LibrarySearchMatch: Identifiable, Sendable {
    case song(DisplayableSong)
    case album(AlbumID3)
    case artist(ArtistID3)
    case playlist(Playlist)

    var id: String {
        switch self {
        case .song(let value): "song:\(value.id)"
        case .album(let value): "album:\(value.id)"
        case .artist(let value): "artist:\(value.id)"
        case .playlist(let value): "playlist:\(value.id)"
        }
    }

    var scope: LibrarySearchScope {
        switch self {
        case .song: .songs
        case .album: .albums
        case .artist: .artists
        case .playlist: .playlists
        }
    }

    var title: String {
        switch self {
        case .song(let value): value.title
        case .album(let value): value.name
        case .artist(let value): value.name
        case .playlist(let value): value.name
        }
    }

    var detail: String {
        switch self {
        case .song(let value): [value.artist, value.albumName].compactMap { $0 }.joined(separator: " ")
        case .album(let value): value.artist ?? ""
        case .artist: ""
        case .playlist(let value): value.comment ?? ""
        }
    }
}

/// A query normalised once, so ranking many candidates doesn't fold and split it per comparison.
nonisolated struct LibrarySearchQuery: Equatable, Sendable {
    let text: String
    let tokens: [Substring]

    init(_ query: String) {
        text = LibrarySearchRanking.normalized(query)
        tokens = text.split(separator: " ")
    }

    var isEmpty: Bool { text.isEmpty }
}

/// A candidate with its title and detail normalised once. The offline snapshot builds these when it
/// loads, so a keystroke only scores them.
nonisolated struct LibrarySearchEntry: Sendable {
    let match: LibrarySearchMatch
    let title: String
    let titleWords: [Substring]
    /// The title followed by the normalised detail, for the last-resort token match.
    let combined: String

    init(_ match: LibrarySearchMatch) {
        self.match = match
        title = LibrarySearchRanking.normalized(match.title)
        titleWords = title.split(separator: " ")
        combined = title + " " + LibrarySearchRanking.normalized(match.detail)
    }
}

/// Ranks existing catalogue matches without a second request. Stable ties keep the list from
/// moving as partial results arrive. Playlist matching uses the cached server-scoped list.
///
/// Each candidate is scored once and sorted on the stored score. The comparators are unchanged, so
/// the order is the one that scoring inside the comparator produced.
nonisolated enum LibrarySearchRanking {
    static func matches(query: String, results: SearchResult3?, playlists: [Playlist]) -> [LibrarySearchMatch] {
        let query = LibrarySearchQuery(query)
        guard !query.isEmpty else { return [] }
        var values: [LibrarySearchMatch] = (results?.artist ?? [])
            .filter { ($0.albumCount ?? 0) > 0 }.map(LibrarySearchMatch.artist)
        values += (results?.album ?? []).map(LibrarySearchMatch.album)
        values += (results?.song ?? []).map { .song(DisplayableSong(from: $0)) }
        var scored = values.map { (match: $0, score: score(LibrarySearchEntry($0), query: query)) }
        scored += playlists.map { (match: LibrarySearchMatch.playlist($0), score: score(LibrarySearchEntry(.playlist($0)), query: query)) }
            .filter { $0.score > 0 }
        var seen = Set<String>()
        return scored.filter { seen.insert($0.match.id).inserted }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let order = lhs.match.title.localizedStandardCompare(rhs.match.title)
            return order == .orderedSame ? lhs.match.id < rhs.match.id : order == .orderedAscending
        }.map(\.match)
    }

    /// Ranks pre-normalised entries and drops those that don't match. Used for downloaded music.
    static func rank(_ entries: [LibrarySearchEntry], query: LibrarySearchQuery) -> [LibrarySearchMatch] {
        guard !query.isEmpty else { return [] }
        return entries.compactMap { entry -> (match: LibrarySearchMatch, score: Int)? in
            let score = score(entry, query: query)
            return score > 0 ? (entry.match, score) : nil
        }.sorted {
            $0.score == $1.score
                ? $0.match.title.localizedStandardCompare($1.match.title) == .orderedAscending
                : $0.score > $1.score
        }.map(\.match)
    }

    static func score(_ match: LibrarySearchMatch, query: String) -> Int {
        score(LibrarySearchEntry(match), query: LibrarySearchQuery(query))
    }

    static func score(_ entry: LibrarySearchEntry, query: LibrarySearchQuery) -> Int {
        guard !query.isEmpty else { return 0 }
        let title = entry.title
        if title == query.text { return 1_000 }
        if title.hasPrefix(query.text) { return 800 }
        if title.contains(query.text) { return 600 }
        if query.tokens.allSatisfy({ token in entry.titleWords.contains { $0.hasPrefix(token) } }) { return 500 }
        return query.tokens.allSatisfy { entry.combined.contains($0) } ? 200 : 0
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
