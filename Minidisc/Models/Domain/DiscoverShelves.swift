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
    static func saved(in playlists: [Playlist]) -> [WrappedYearlyPlaylist] {
        let prefix = WrappedPlaylistService.wrappedPlaylistNamePrefix
        return playlists.compactMap { playlist in
            guard playlist.name.hasPrefix(prefix), let year = Int(playlist.name.dropFirst(prefix.count)) else { return nil }
            return WrappedYearlyPlaylist(id: playlist.id, year: year, name: playlist.name, coverArtId: playlist.coverArt)
        }
    }
}

extension MoodPlaylist {
    /// The mood playlists among `playlists`, recognised by name, e.g. the ones saved offline.
    static func saved(in playlists: [Playlist]) -> [MoodPlaylist] {
        playlists.compactMap { playlist in
            guard let mood = Mood.allCases.first(where: { $0.playlistName == playlist.name }) else { return nil }
            return MoodPlaylist(mood: mood, id: playlist.id, coverArtId: playlist.coverArt)
        }
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
