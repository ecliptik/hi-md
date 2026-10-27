import Foundation
import SwiftSonic

/// A card on Discover's Wrapped shelf and the Wrapped page.
enum WrappedCarouselItem: Identifiable {
    /// A finished year, with its server playlist.
    case yearly(WrappedYearlyPlaylist)
    /// This year, before its playlist exists.
    case currentYear(Int)
    /// A month of this year, for its listening recap.
    case month(year: Int, month: Int)

    var id: String {
        switch self {
        case .yearly(let playlist): "yearly-\(playlist.id)"
        case .currentYear(let year): "current-\(year)"
        case .month(let year, let month): "month-\(year)-\(month)"
        }
    }

    /// Discover's shelf: the yearly playlists, this year while it has none, then this year's
    /// months, newest first.
    static func shelfItems(yearly: [WrappedYearlyPlaylist], now: Date = Date(), calendar: Calendar = .current) -> [WrappedCarouselItem] {
        let year = calendar.component(.year, from: now)
        var items = yearly.map(WrappedCarouselItem.yearly)
        if !yearly.contains(where: { $0.year == year }) { items.append(.currentYear(year)) }
        items += months(now: now, calendar: calendar)
        return items
    }

    /// The Wrapped page: this year first while it has no playlist, then the yearly playlists and
    /// this year's months, newest first.
    static func pageItems(yearly: [WrappedYearlyPlaylist], now: Date = Date(), calendar: Calendar = .current) -> [WrappedCarouselItem] {
        let year = calendar.component(.year, from: now)
        var items: [WrappedCarouselItem] = yearly.contains(where: { $0.year == year }) ? [] : [.currentYear(year)]
        items += yearly.map(WrappedCarouselItem.yearly)
        items += months(now: now, calendar: calendar)
        return items
    }

    private static func months(now: Date, calendar: Calendar) -> [WrappedCarouselItem] {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return (1...month).reversed().map { .month(year: year, month: $0) }
    }
}

extension WrappedYearlyPlaylist {
    /// The Wrapped playlists among `playlists`, recognised by name, e.g. the ones saved offline.
    /// Both the Hi-MD and the older Minidisc names count; a year with both uses the Hi-MD one.
    nonisolated static func saved(in playlists: [Playlist]) -> [WrappedYearlyPlaylist] {
        playlists.preferringCurrentNames { playlist -> (key: Int, isLegacy: Bool)? in
            if let year = WrappedPlaylistService.legacyWrappedYear(fromPlaylistName: playlist.name) { return (year, true) }
            return WrappedPlaylistService.wrappedYear(fromPlaylistName: playlist.name).map { ($0, false) }
        }
        .map { WrappedYearlyPlaylist(id: $0.playlist.id, year: $0.key, name: $0.playlist.name, coverArtId: $0.playlist.coverArt) }
    }
}

extension MoodPlaylist {
    /// The mood playlists among `playlists`, recognised by name, e.g. the ones saved offline.
    /// Both the Hi-MD and the older Minidisc names count; a mood with both uses the Hi-MD one.
    nonisolated static func saved(in playlists: [Playlist]) -> [MoodPlaylist] {
        playlists.preferringCurrentNames { playlist -> (key: Mood, isLegacy: Bool)? in
            Mood.forPlaylistName(playlist.name).map { ($0, $0.legacyPlaylistName == playlist.name) }
        }
        .map { MoodPlaylist(mood: $0.key, id: $0.playlist.id, coverArtId: $0.playlist.coverArt) }
    }
}

enum SmartShuffleArtwork {
    /// Up to three different covers for the Smart Shuffle card, from the albums given.
    static func coverIDs(_ albums: [AlbumID3], limit: Int = 3) -> [String] {
        var seen = Set<String>()
        return albums.map { $0.coverArt ?? $0.id }
            .filter { seen.insert($0).inserted }
            .prefix(limit).map { $0 }
    }
}
