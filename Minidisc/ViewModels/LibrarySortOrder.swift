import Foundation
import SwiftSonic

/// Which way a sort runs, the second half of the Mac's sort menus.
nonisolated enum SortDirection: String, CaseIterable, Sendable {
    case ascending
    case descending

    var title: LocalizedStringResource {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}

/// What a list can be sorted by, the first half of the Mac's sort menus.
nonisolated protocol LibrarySortField: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    var title: LocalizedStringResource { get }
    /// The way the field reads naturally: names A to Z, dates and counts newest or most first.
    var defaultDirection: SortDirection { get }
}

/// A list's sort as the Music app's sort menu sets it: a field and a direction. Stored with
/// `@AppStorage` as "field:direction"; a bare field, as the Mac stored its album and artist
/// sorts before, reads with the field's own direction.
nonisolated struct LibrarySortOrder<Field: LibrarySortField>: RawRepresentable, Hashable, Sendable {
    var field: Field
    var direction: SortDirection

    init(_ field: Field, _ direction: SortDirection? = nil) {
        self.field = field
        self.direction = direction ?? field.defaultDirection
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first, let field = Field(rawValue: first) else { return nil }
        if parts.count == 2 {
            guard let direction = SortDirection(rawValue: parts[1]) else { return nil }
            self.init(field, direction)
        } else {
            self.init(field)
        }
    }

    var rawValue: String { "\(field.rawValue):\(direction.rawValue)" }

    var isAscending: Bool { direction == .ascending }

    /// Choosing a field from the menu: another field starts in its own direction, as a click on
    /// a new column does; the same field keeps the direction.
    mutating func select(_ field: Field) {
        guard field != self.field else { return }
        self.field = field
        direction = field.defaultDirection
    }

    /// Orders by `primary`, which compares ascending; missing values (`.orderedSame` with
    /// `isMissing`) aside, ties fall back to `tieBreak`, always ascending.
    fileprivate func ordered(_ primary: ComparisonResult, tieBreak: ComparisonResult) -> Bool {
        let result = primary == .orderedSame ? tieBreak : (isAscending ? primary : primary.reversed)
        return result == .orderedAscending
    }
}

private extension ComparisonResult {
    nonisolated var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

nonisolated private enum SortCompare {
    /// Text the way the Finder sorts it.
    static func text(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedStandardCompare(rhs)
    }

    static func value<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }
}

// MARK: - Albums

nonisolated enum AlbumSortField: String, LibrarySortField {
    /// The raw values are the ones the Mac's album sort stored before, so it carries over.
    case name
    case artist
    case releaseYear
    case recentlyAdded

    var title: LocalizedStringResource {
        switch self {
        case .name: "Title"
        case .artist: "Artist"
        case .releaseYear: "Year"
        case .recentlyAdded: "Recently Added"
        }
    }

    var defaultDirection: SortDirection {
        switch self {
        case .name, .artist: .ascending
        case .releaseYear, .recentlyAdded: .descending
        }
    }
}

extension LibrarySortOrder where Field == AlbumSortField {
    /// Orders albums. Albums without a year, date or artist go last either way; ties keep
    /// title order.
    func sorted(_ albums: [AlbumID3]) -> [AlbumID3] {
        func title(_ album: AlbumID3) -> String { album.sortName ?? album.name }
        return albums.sorted { lhs, rhs in
            let tie = SortCompare.text(title(lhs), title(rhs))
            switch field {
            case .name:
                return ordered(tie, tieBreak: .orderedSame)
            case .artist:
                switch (lhs.artist?.isEmpty == false ? lhs.artist : nil, rhs.artist?.isEmpty == false ? rhs.artist : nil) {
                case let (left?, right?): return ordered(SortCompare.text(left, right), tieBreak: tie)
                case (nil, nil): return tie == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            case .releaseYear:
                switch (lhs.year, rhs.year) {
                case let (left?, right?): return ordered(SortCompare.value(left, right), tieBreak: tie)
                case (nil, nil): return tie == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            case .recentlyAdded:
                switch (lhs.created, rhs.created) {
                case let (left?, right?): return ordered(SortCompare.value(left, right), tieBreak: tie)
                case (nil, nil): return tie == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }
}

// MARK: - Artists

nonisolated enum ArtistSortField: String, LibrarySortField {
    case name
    case albumCount

    var title: LocalizedStringResource {
        switch self {
        case .name: "Name"
        case .albumCount: "Album Count"
        }
    }

    var defaultDirection: SortDirection {
        switch self {
        case .name: .ascending
        case .albumCount: .descending
        }
    }
}

extension LibrarySortOrder where Field == ArtistSortField {
    func sorted(_ artists: [ArtistID3]) -> [ArtistID3] {
        func name(_ artist: ArtistID3) -> String { artist.sortName ?? artist.name }
        return artists.sorted { lhs, rhs in
            let tie = SortCompare.text(name(lhs), name(rhs))
            switch field {
            case .name:
                return ordered(tie, tieBreak: .orderedSame)
            case .albumCount:
                return ordered(SortCompare.value(lhs.albumCount ?? 0, rhs.albumCount ?? 0), tieBreak: tie)
            }
        }
    }
}

// MARK: - Songs

/// The song tables' sorts, the same as clicking their column headers.
nonisolated enum SongSortField: String, LibrarySortField {
    /// The list's own order: the playlist's.
    case position
    case title
    case artist
    case album
    case genre
    case duration

    var title: LocalizedStringResource {
        switch self {
        case .position: "Playlist Order"
        case .title: "Title"
        case .artist: "Artist"
        case .album: "Album"
        case .genre: "Genre"
        case .duration: "Time"
        }
    }

    var defaultDirection: SortDirection { .ascending }

    var column: SongTableComparator.Column {
        switch self {
        case .position: .position
        case .title: .title
        case .artist: .artist
        case .album: .album
        case .genre: .genre
        case .duration: .duration
        }
    }

    init(column: SongTableComparator.Column) {
        switch column {
        case .position: self = .position
        case .title: self = .title
        case .artist: self = .artist
        case .album: self = .album
        case .genre: self = .genre
        case .duration: self = .duration
        }
    }

    /// Every field but the list's own order, for lists without one worth keeping.
    static let withoutPosition: [SongSortField] = allCases.filter { $0 != .position }
}

extension LibrarySortOrder where Field == SongSortField {
    /// The table's comparator for this sort.
    var comparator: SongTableComparator {
        SongTableComparator(column: field.column, order: isAscending ? .forward : .reverse)
    }

    /// The sort a click on a column header asked for.
    init(comparator: SongTableComparator) {
        self.init(SongSortField(column: comparator.column), comparator.order == .forward ? .ascending : .descending)
    }

    /// Whether the list shows in its own order, which dragging rows to rearrange needs.
    var isListOrder: Bool { field == .position && isAscending }

    /// The songs in the order the table shows them, for Play.
    func sorted(_ songs: [DisplayableSong]) -> [DisplayableSong] {
        guard !isListOrder else { return songs }
        return SongTableRow.rows(songs).sorted(using: comparator).map(\.song)
    }
}
