import Foundation
import SwiftSonic

/// The library operations needed to turn decoded playlist entries back into songs. The search
/// service or a SwiftSonic client can satisfy it; tests use a fake.
nonisolated protocol M3USongLookup: Sendable {
    /// Nil when the server has no song with this ID.
    func song(id: String) async throws -> Song?
    /// Songs matching a free-text query, as from `search3`. Results should include `path`.
    func searchSongs(_ query: String) async throws -> [Song]
}

nonisolated struct M3UResolution: Sendable {
    enum Match: Sendable, Equatable {
        case songID
        case path
        case artistAndTitle
        case unresolved
    }

    let entry: M3UPlaylist.Entry
    let song: Song?
    let match: Match
}

/// Resolves entries by song ID, then by server path, then by artist and title. Subsonic has no
/// lookup by path, so both path and tag matching search by title and compare the results.
nonisolated struct M3UPlaylistResolver: Sendable {
    let lookup: any M3USongLookup
    /// Seconds of difference still treated as the same recording when titles collide.
    private let durationTolerance = 3

    init(lookup: any M3USongLookup) {
        self.lookup = lookup
    }

    /// Entries resolved at once, so a long playlist doesn't flood the server.
    static let maximumConcurrentLookups = 4

    /// Resolves the first `M3UPlaylist.maximumEntries` entries, up to four at a time, and returns
    /// them in playlist order. Searches are shared per query, so repeated titles cost one request.
    func resolve(_ entries: [M3UPlaylist.Entry]) async throws -> [M3UResolution] {
        try Task.checkCancellation()
        let entries = Array(entries.prefix(M3UPlaylist.maximumEntries))
        let searches = SearchCache(lookup: lookup)
        var results = [M3UResolution?](repeating: nil, count: entries.count)
        try await withThrowingTaskGroup(of: (Int, M3UResolution).self) { group in
            var next = 0
            while next < min(Self.maximumConcurrentLookups, entries.count) {
                let index = next
                group.addTask { (index, try await resolve(entries[index], searches: searches)) }
                next += 1
            }
            while let (index, resolution) = try await group.next() {
                results[index] = resolution
                guard next < entries.count else { continue }
                let following = next
                group.addTask { (following, try await resolve(entries[following], searches: searches)) }
                next += 1
            }
        }
        return results.compactMap(\.self)
    }

    /// One search per query, shared by entries resolving at the same time.
    private actor SearchCache {
        private let lookup: any M3USongLookup
        private var searches: [String: Task<[Song], any Error>] = [:]

        init(lookup: any M3USongLookup) {
            self.lookup = lookup
        }

        func songs(matching query: String) async throws -> [Song] {
            if let search = searches[query] { return try await search.value }
            let lookup = lookup
            let search = Task { try await lookup.searchSongs(query).filter { $0.isDir != true } }
            searches[query] = search
            return try await search.value
        }
    }

    private func resolve(_ entry: M3UPlaylist.Entry, searches: SearchCache) async throws -> M3UResolution {
        try Task.checkCancellation()
        if let id = entry.songID, let song = try await lookup.song(id: id) {
            return M3UResolution(entry: entry, song: song, match: .songID)
        }
        let tags = Self.tags(for: entry)
        guard let query = tags.title.map(Self.searchQuery), !query.isEmpty else {
            return M3UResolution(entry: entry, song: nil, match: .unresolved)
        }
        let candidates = try await searches.songs(matching: query)
        if let components = entry.pathComponents,
           let song = Self.pathMatch(components, in: candidates) {
            return M3UResolution(entry: entry, song: song, match: .path)
        }
        if let song = tagMatch(tags, duration: entry.duration, in: candidates) {
            return M3UResolution(entry: entry, song: song, match: .artistAndTitle)
        }
        return M3UResolution(entry: entry, song: nil, match: .unresolved)
    }

    // MARK: Path matching

    /// The shorter path must be a suffix of the longer one. A bare file name only counts when one
    /// candidate has it, since many albums have a "01 Intro.flac".
    static func pathMatch(_ components: [String], in candidates: [Song]) -> Song? {
        let matches = candidates.filter { song in
            guard let path = song.path else { return false }
            let songComponents = path.split(separator: "/").map { M3UPlaylist.foldedComponent(String($0)) }
            let shorter = min(songComponents.count, components.count)
            guard shorter > 0 else { return false }
            return songComponents.suffix(shorter) == components.suffix(shorter)
        }
        if components.count == 1 { return matches.count == 1 ? matches.first : nil }
        return matches.first
    }

    // MARK: Tag matching

    struct Tags: Equatable {
        var artist: String?
        var title: String?
    }

    /// Tags from `#EXTINF`, or else from an `Artist/Album/NN - Title.ext` path.
    static func tags(for entry: M3UPlaylist.Entry) -> Tags {
        if let title = entry.title {
            return Tags(artist: entry.artist, title: title)
        }
        guard let components = rawPathComponents(entry.location), let file = components.last else {
            return Tags()
        }
        let stem = (file as NSString).deletingPathExtension
        let title = stripTrackNumber(stem)
        let artist = components.count >= 3 ? components[components.count - 3] : nil
        return Tags(artist: artist, title: title.isEmpty ? nil : title)
    }

    private func tagMatch(_ tags: Tags, duration: Int?, in candidates: [Song]) -> Song? {
        guard let title = tags.title.map(Self.normalized) else { return nil }
        var matches = candidates.filter { Self.normalized($0.title) == title }
        if let artist = tags.artist.map(Self.normalized) {
            matches = matches.filter { song in
                let names = [song.artist, song.displayArtist] + (song.artists ?? []).map(\.name)
                return names.compactMap { $0 }.contains { Self.normalized($0) == artist }
            }
        } else if matches.count > 1, duration == nil {
            return nil
        }
        if let duration, matches.count > 1 {
            let closest = matches.filter { song in
                song.duration.map { abs($0 - duration) <= durationTolerance } ?? false
            }
            if !closest.isEmpty { matches = closest }
        }
        return matches.first
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func searchQuery(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "01 - Title", "1-01 Title", "01. Title" → "Title".
    static func stripTrackNumber(_ stem: String) -> String {
        let pattern = /^\s*(\d{1,3}[-.]\s*)?\d{1,3}\s*([-.]\s*|\s+)/
        if let match = stem.firstMatch(of: pattern), match.range.upperBound < stem.endIndex {
            return String(stem[match.range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return stem.trimmingCharacters(in: .whitespaces)
    }

    /// Unfolded components, for reading tag text out of folder and file names.
    private static func rawPathComponents(_ location: String) -> [String]? {
        if let scheme = URLComponents(string: location)?.scheme?.lowercased(), scheme.count > 1 {
            guard scheme == "file", let url = URL(string: location) else { return nil }
            return url.pathComponents.filter { $0 != "/" }
        }
        let components = location.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init)
        return components.isEmpty ? nil : components
    }
}
