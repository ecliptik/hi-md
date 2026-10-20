import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Smart search filters")
struct LibraryQueryFilterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    @Test func mellowNinetiesRockNotPlayedLately() {
        var query = LibraryQuery()
        query.genres = ["rock"]
        query.years = 1990...1999
        query.mood = .chill
        query.recency = .notPlayedLately
        let match = Song(id: "1", title: "Slow", year: 1994, genre: "Alternative Rock", played: now - 200 * day, bpm: 90)
        let neverPlayed = Song(id: "2", title: "Unheard", year: 1997, genre: "Post-Rock")
        let tooFast = Song(id: "3", title: "Fast", year: 1994, genre: "Rock", bpm: 160)
        let recent = Song(id: "4", title: "Recent", year: 1994, genre: "Rock", played: now - 3 * day)
        let wrongDecade = Song(id: "5", title: "Later", year: 2004, genre: "Rock")
        let wrongGenre = Song(id: "6", title: "Jazz", year: 1994, genre: "Jazz")
        let noYear = Song(id: "7", title: "Undated", genre: "Rock")
        let ids = [match, neverPlayed, tooFast, recent, wrongDecade, wrongGenre, noYear]
            .filter { LibraryQueryFilter.matches($0, query, now: now) }.map(\.id)
        #expect(ids == ["1", "2"])
    }

    @Test func moodAloneUsesItsGenresOrTempo() {
        var query = LibraryQuery()
        query.mood = .focus
        #expect(LibraryQueryFilter.matches(Song(id: "a", title: "A", genre: "Modern Classical"), query, now: now))
        #expect(!LibraryQueryFilter.matches(Song(id: "b", title: "B", genre: "Punk"), query, now: now))
        query.mood = .workout
        #expect(LibraryQueryFilter.matches(Song(id: "c", title: "C", genre: "Pop", bpm: 140), query, now: now))
    }

    @Test func artistsFavoritesAndRecentPlays() {
        var query = LibraryQuery()
        query.artists = ["radiohead"]
        query.favoritesOnly = true
        query.recency = .playedRecently
        let loved = Song(id: "1", title: "Lucky", artist: "Radiohead", starred: now - day, played: now - 2 * day)
        let notLoved = Song(id: "2", title: "Creep", artist: "Radiohead", played: now - 2 * day)
        let guest = Song(id: "3", title: "Feat", starred: now, played: now - day,
                         artists: [ArtistID3(id: "r", name: "Radiohead")])
        let stale = Song(id: "4", title: "Old", artist: "Radiohead", starred: now, played: now - 60 * day)
        let ids = [loved, notLoved, guest, stale].filter { LibraryQueryFilter.matches($0, query, now: now) }.map(\.id)
        #expect(ids == ["1", "3"])
    }

    @Test func rankingFavorsLovedSongsAndSpreadsAlbums() {
        let album: [Song] = (0..<8).map { (i: Int) in Song(id: "a\(i)", title: "Track \(i)", playCount: i, albumId: "big") }
        let songs = album + [Song(id: "s", title: "Starred", starred: now, albumId: "small")]
        let ranked = LibraryQueryFilter.rank(songs)
        #expect(Array(ranked.map(\.id).prefix(2)) == ["s", "a7"])
        #expect(ranked.count { $0.albumId == "big" } == LibraryQueryFilter.perAlbumLimit)
    }

    @Test func emptyInterpretationIsRejectedAndSummarized() {
        #expect(LibraryQuery().isEmpty)
        var query = LibraryQuery()
        query.genres = ["rock"]
        query.years = 1990...1999
        query.recency = .notPlayedLately
        #expect(!query.isEmpty)
        #expect(query.summary == ["Rock", "1990–1999", String(localized: "Not played lately")])
    }
}
