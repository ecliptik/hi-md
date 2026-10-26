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
