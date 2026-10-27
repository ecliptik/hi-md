import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Mac sort menus: fields and directions")
struct LibrarySortOrderTests {
    private func album(_ name: String, artist: String? = nil, year: Int? = nil, added: TimeInterval? = nil) -> AlbumID3 {
        AlbumID3(id: name, name: name, songCount: 1, duration: 60, artist: artist,
                 created: added.map { Date(timeIntervalSince1970: $0) }, year: year)
    }

    private func song(_ id: String, title: String, duration: TimeInterval = 120) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title, artist: "Artist", albumId: nil, albumName: "Album", artistId: nil, genre: nil,
            duration: duration, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    // MARK: Storage

    @Test func itIsStoredAsFieldAndDirection() {
        let order = LibrarySortOrder<AlbumSortField>(.releaseYear, .ascending)
        #expect(order.rawValue == "releaseYear:ascending")
        #expect(LibrarySortOrder<AlbumSortField>(rawValue: order.rawValue) == order)
        #expect(LibrarySortOrder<AlbumSortField>(rawValue: "nonsense") == nil)
        #expect(LibrarySortOrder<AlbumSortField>(rawValue: "name:sideways") == nil)
    }

    @Test func theOldBareSortsCarryOver() {
        // The Mac stored AlbumSort's and ArtistSort's raw values before.
        #expect(LibrarySortOrder<AlbumSortField>(rawValue: "name") == LibrarySortOrder(.name, .ascending))
        #expect(LibrarySortOrder<AlbumSortField>(rawValue: "recentlyAdded") == LibrarySortOrder(.recentlyAdded, .descending))
        #expect(LibrarySortOrder<AlbumSortField>(rawValue: "releaseYear") == LibrarySortOrder(.releaseYear, .descending))
        #expect(LibrarySortOrder<ArtistSortField>(rawValue: "albumCount") == LibrarySortOrder(.albumCount, .descending))
        for old in AlbumSort.allCases {
            #expect(AlbumSortField(rawValue: old.rawValue) != nil)
        }
        for old in ArtistSort.allCases {
            #expect(ArtistSortField(rawValue: old.rawValue) != nil)
        }
    }

    // MARK: The menu

    @Test func choosingAnotherFieldStartsInItsOwnDirection() {
        var order = LibrarySortOrder<AlbumSortField>(.name)
        order.direction = .descending
        // Same field: the direction stays.
        order.select(.name)
        #expect(order.direction == .descending)
        order.select(.recentlyAdded)
        #expect(order == LibrarySortOrder(.recentlyAdded, .descending))
        order.select(.artist)
        #expect(order.direction == .ascending)
        #expect(SortDirection.allCases == [.ascending, .descending])
    }

    // MARK: Sorting

    @Test func albumsSortByEachFieldBothWays() {
        let albums = [album("b", artist: "Zed", year: 1999, added: 10), album("a", artist: "Abba", year: 2020, added: 30),
                      album("c", artist: nil, year: nil, added: nil)]
        #expect(LibrarySortOrder<AlbumSortField>(.name).sorted(albums).map(\.name) == ["a", "b", "c"])
        #expect(LibrarySortOrder<AlbumSortField>(.name, .descending).sorted(albums).map(\.name) == ["c", "b", "a"])
        #expect(LibrarySortOrder<AlbumSortField>(.artist).sorted(albums).map(\.name) == ["a", "b", "c"])
        #expect(LibrarySortOrder<AlbumSortField>(.artist, .descending).sorted(albums).map(\.name) == ["b", "a", "c"])
        // Newest first by default; missing years and dates go last either way.
        #expect(LibrarySortOrder<AlbumSortField>(.releaseYear).sorted(albums).map(\.name) == ["a", "b", "c"])
        #expect(LibrarySortOrder<AlbumSortField>(.releaseYear, .ascending).sorted(albums).map(\.name) == ["b", "a", "c"])
        #expect(LibrarySortOrder<AlbumSortField>(.recentlyAdded).sorted(albums).map(\.name) == ["a", "b", "c"])
        #expect(LibrarySortOrder<AlbumSortField>(.recentlyAdded, .ascending).sorted(albums).map(\.name) == ["b", "a", "c"])
    }

    @Test func tiesKeepTitleOrder() {
        let albums = [album("Zebra", year: 2000), album("apple", year: 2000), album("Mango", year: 2000)]
        #expect(LibrarySortOrder<AlbumSortField>(.releaseYear).sorted(albums).map(\.name) == ["apple", "Mango", "Zebra"])
        #expect(LibrarySortOrder<AlbumSortField>(.releaseYear, .ascending).sorted(albums).map(\.name)
                == ["apple", "Mango", "Zebra"])
    }

    @Test func artistsSortByNameOrAlbumCount() {
        let artists = [ArtistID3(id: "1", name: "Bowie", albumCount: 3), ArtistID3(id: "2", name: "ABBA", albumCount: 9),
                       ArtistID3(id: "3", name: "Cure", albumCount: 3)]
        #expect(LibrarySortOrder<ArtistSortField>(.name).sorted(artists).map(\.name) == ["ABBA", "Bowie", "Cure"])
        #expect(LibrarySortOrder<ArtistSortField>(.albumCount).sorted(artists).map(\.name) == ["ABBA", "Bowie", "Cure"])
        #expect(LibrarySortOrder<ArtistSortField>(.albumCount, .ascending).sorted(artists).map(\.name)
                == ["Bowie", "Cure", "ABBA"])
    }

    @Test func songSortsAreTheTablesColumns() {
        let order = LibrarySortOrder<SongSortField>(.duration, .descending)
        #expect(order.comparator == SongTableComparator(column: .duration, order: .reverse))
        #expect(LibrarySortOrder(comparator: SongTableComparator(column: .title)) == LibrarySortOrder<SongSortField>(.title))
        for field in SongSortField.allCases {
            #expect(SongSortField(column: field.column) == field)
        }
        #expect(!SongSortField.withoutPosition.contains(.position))
        // Only the playlist's own order lets rows be dragged to rearrange it.
        #expect(LibrarySortOrder<SongSortField>(.position).isListOrder)
        #expect(!LibrarySortOrder<SongSortField>(.position, .descending).isListOrder)
        #expect(!LibrarySortOrder<SongSortField>(.title).isListOrder)
    }

    @Test func playPlaysTheSongsAsShown() {
        let songs = [song("1", title: "Cee", duration: 200), song("2", title: "Ay", duration: 100),
                     song("3", title: "Bee", duration: 300)]
        #expect(LibrarySortOrder<SongSortField>(.position).sorted(songs).map(\.id) == ["1", "2", "3"])
        #expect(LibrarySortOrder<SongSortField>(.position, .descending).sorted(songs).map(\.id) == ["3", "2", "1"])
        #expect(LibrarySortOrder<SongSortField>(.title).sorted(songs).map(\.id) == ["2", "3", "1"])
        #expect(LibrarySortOrder<SongSortField>(.duration, .descending).sorted(songs).map(\.id) == ["3", "1", "2"])
    }
}
