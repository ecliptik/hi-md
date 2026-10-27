import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Discover shelves")
@MainActor
struct DiscoverShelvesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(year: Int, month: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 15))!
    }

    private func yearly(_ year: Int) -> WrappedYearlyPlaylist {
        WrappedYearlyPlaylist(id: "w\(year)", year: year, name: "\(WrappedPlaylistService.wrappedPlaylistNamePrefix)\(year)", coverArtId: nil)
    }

    @Test("The Wrapped shelf lists the yearly playlists, this year while it has none, then this year's months")
    func shelfItems() {
        let items = WrappedCarouselItem.shelfItems(yearly: [yearly(2025)], now: date(year: 2026, month: 3), calendar: calendar)
        #expect(items.map(\.id) == ["yearly-w2025", "current-2026", "month-2026-3", "month-2026-2", "month-2026-1"])
    }

    @Test("This year's playlist replaces its placeholder card")
    func currentYearPlaylist() {
        let items = WrappedCarouselItem.shelfItems(yearly: [yearly(2026)], now: date(year: 2026, month: 1), calendar: calendar)
        #expect(items.map(\.id) == ["yearly-w2026", "month-2026-1"])
    }

    @Test("The Wrapped page puts this year first")
    func pageItems() {
        let items = WrappedCarouselItem.pageItems(yearly: [yearly(2025)], now: date(year: 2026, month: 2), calendar: calendar)
        #expect(items.map(\.id) == ["current-2026", "yearly-w2025", "month-2026-2", "month-2026-1"])
    }

    @Test("Every Wrapped card has its period and a caption to show")
    func cardText() {
        let english = Locale(identifier: "en_US")
        let items = WrappedCarouselItem.shelfItems(yearly: [yearly(2025)], now: date(year: 2026, month: 10), calendar: calendar)
        #expect(items.prefix(4).map { $0.cardTitle(calendar: calendar, locale: english) } == ["2025", "2026", "October", "September"])
        #expect(items.prefix(4).map(\.cardSubtitle) == [String(localized: "Wrapped"), String(localized: "Wrapped"), "2026", "2026"])
        #expect(items.prefix(4).map(\.year) == [2025, 2026, 2026, 2026])
        #expect(items.allSatisfy { !$0.cardTitle(calendar: calendar).isEmpty && !$0.cardSubtitle.isEmpty })
        #expect(WrappedCarouselItem.month(year: 2026, month: 1).cardTitle(calendar: calendar, locale: Locale(identifier: "fr_FR")) == "janvier")
    }

    @Test("Saved Wrapped and mood playlists are recognised by name")
    func savedPlaylists() {
        let prefix = WrappedPlaylistService.wrappedPlaylistNamePrefix
        let playlists = [
            Playlist(id: "a", name: "\(prefix)2024", songCount: 1, duration: 1),
            Playlist(id: "b", name: "\(prefix)Best", songCount: 1, duration: 1),
            Playlist(id: "c", name: Mood.chill.playlistName, songCount: 1, duration: 1),
            Playlist(id: "d", name: "Chill", songCount: 1, duration: 1),
        ]
        #expect(WrappedYearlyPlaylist.saved(in: playlists).map(\.year) == [2024])
        #expect(MoodPlaylist.saved(in: playlists) == [MoodPlaylist(mood: .chill, id: "c", coverArtId: nil)])
    }

    @Test("Smart Shuffle's artwork uses up to three different covers")
    func shuffleCovers() {
        let albums = [
            AlbumID3(id: "1", name: "One", songCount: 1, duration: 1, coverArt: "x"),
            AlbumID3(id: "2", name: "Two", songCount: 1, duration: 1, coverArt: "x"),
            AlbumID3(id: "3", name: "Three", songCount: 1, duration: 1),
            AlbumID3(id: "4", name: "Four", songCount: 1, duration: 1, coverArt: "y"),
            AlbumID3(id: "5", name: "Five", songCount: 1, duration: 1, coverArt: "z"),
        ]
        #expect(SmartShuffleArtwork.coverIDs(albums) == ["x", "3", "y"])
        #expect(SmartShuffleArtwork.coverIDs([]).isEmpty)
    }
}
