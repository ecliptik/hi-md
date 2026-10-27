import Foundation

/// A song at its place in a list, as the Mac app's song tables show it. Playlists can hold the
/// same song more than once, so a row is identified by its position, not by the song's ID.
nonisolated struct SongTableRow: Identifiable, Hashable, Sendable {
    let position: Int
    let song: DisplayableSong

    var id: Int { position }

    static func rows(_ songs: [DisplayableSong]) -> [SongTableRow] {
        songs.enumerated().map { SongTableRow(position: $0.offset, song: $0.element) }
    }
}

/// A song in an iPhone list that can hold it more than once (a playlist, its editor), identified
/// by the song's ID and which occurrence of it this is. Keyed by the song alone, the second copy
/// gave the List a duplicate identifier, which breaks its deletes, moves and selection. A song
/// that's there once keeps its identity as it moves.
nonisolated struct SongOccurrence: Identifiable, Hashable, Sendable {
    struct ID: Hashable, Sendable {
        let songID: String
        let occurrence: Int
    }

    let id: ID
    /// Its position in the list.
    let index: Int
    let song: DisplayableSong

    static func list(_ songs: [DisplayableSong]) -> [SongOccurrence] {
        var seen: [String: Int] = [:]
        return songs.enumerated().map { index, song in
            let occurrence = seen[song.id, default: 0]
            seen[song.id] = occurrence + 1
            return SongOccurrence(id: ID(songID: song.id, occurrence: occurrence), index: index, song: song)
        }
    }
}

/// A playlist's songs as a list shows them, sorted or filtered locally, each row knowing its
/// position in the playlist's stored order: the server's order, which Subsonic's
/// `songIndexToRemove` counts in. A song the playlist holds twice is two rows with two
/// positions, so removing a row removes that copy, not the first one.
nonisolated struct PlaylistRowPositions: Equatable, Sendable {
    /// The stored position of each shown row, in the order the rows are shown.
    let positions: [Int]

    /// - Parameters:
    ///   - songs: The playlist's songs in stored order.
    ///   - areInIncreasingOrder: The list's sort, or nil for the playlist's own order. Songs that
    ///     tie keep their playlist order.
    ///   - isIncluded: The list's filter, or nil to show every song.
    init(_ songs: [DisplayableSong],
         sortedBy areInIncreasingOrder: ((DisplayableSong, DisplayableSong) -> Bool)? = nil,
         where isIncluded: ((DisplayableSong) -> Bool)? = nil) {
        var shown = Array(songs.indices)
        if let isIncluded { shown = shown.filter { isIncluded(songs[$0]) } }
        if let areInIncreasingOrder {
            shown.sort { lhs, rhs in
                if areInIncreasingOrder(songs[lhs], songs[rhs]) { return true }
                if areInIncreasingOrder(songs[rhs], songs[lhs]) { return false }
                return lhs < rhs
            }
        }
        positions = shown
    }

    /// The shown songs, in the order they're shown.
    func rows(of songs: [DisplayableSong]) -> [DisplayableSong] {
        positions.compactMap { songs.indices.contains($0) ? songs[$0] : nil }
    }

    /// The stored positions of the shown rows at `offsets`, highest first and each once, so they
    /// can be removed in one go without one removal moving the next.
    func storedPositions(ofRows offsets: some Sequence<Int>) -> [Int] {
        Set(offsets.compactMap { positions.indices.contains($0) ? positions[$0] : nil }).sorted(by: >)
    }
}

/// Orders song table rows by one column. Text compares the way the Finder does (ignoring case,
/// numbers in numeric order) and missing values sort after names. Equal values keep the list's order
/// in both directions, so clicking a column twice never shuffles tracks that tie.
nonisolated struct SongTableComparator: SortComparator, Hashable, Sendable {
    enum Column: String, Hashable, Sendable {
        /// The list's own order: track order on an album, the playlist's order in a playlist.
        case position
        case title
        case artist
        /// Album name, then disc and track number, so an album's songs stay together in order.
        case album
        case genre
        case duration
    }

    var column: Column
    var order: SortOrder = .forward

    func compare(_ lhs: SongTableRow, _ rhs: SongTableRow) -> ComparisonResult {
        let primary = ascending(lhs.song, rhs.song)
        if primary != .orderedSame, column != .position {
            return order == .forward ? primary : primary.flipped
        }
        let byPosition = Self.compare(lhs.position, rhs.position)
        return column == .position && order == .reverse ? byPosition.flipped : byPosition
    }

    private func ascending(_ lhs: DisplayableSong, _ rhs: DisplayableSong) -> ComparisonResult {
        switch column {
        case .position:
            return .orderedSame
        case .title:
            return Self.compareText(lhs.title, rhs.title)
        case .artist:
            let byArtist = Self.compareText(lhs.artist, rhs.artist)
            return byArtist != .orderedSame ? byArtist : Self.compareAlbumOrder(lhs, rhs)
        case .album:
            return Self.compareAlbumOrder(lhs, rhs)
        case .genre:
            return Self.compareText(lhs.genre, rhs.genre)
        case .duration:
            return Self.compare(lhs.duration, rhs.duration)
        }
    }

    private static func compareAlbumOrder(_ lhs: DisplayableSong, _ rhs: DisplayableSong) -> ComparisonResult {
        let byAlbum = compareText(lhs.albumName, rhs.albumName)
        if byAlbum != .orderedSame { return byAlbum }
        let byDisc = compare(lhs.discNumber ?? 1, rhs.discNumber ?? 1)
        if byDisc != .orderedSame { return byDisc }
        return compare(lhs.trackNumber ?? .max, rhs.trackNumber ?? .max)
    }

    /// Missing or blank text sorts after every name when ascending.
    private static func compareText(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        let left = lhs?.trimmingCharacters(in: .whitespaces) ?? ""
        let right = rhs?.trimmingCharacters(in: .whitespaces) ?? ""
        switch (left.isEmpty, right.isEmpty) {
        case (true, true): return .orderedSame
        case (true, false): return .orderedDescending
        case (false, true): return .orderedAscending
        case (false, false): return left.localizedStandardCompare(right)
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
}

private extension ComparisonResult {
    nonisolated var flipped: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}
