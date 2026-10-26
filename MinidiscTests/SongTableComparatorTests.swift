import Foundation
import Testing
@testable import Minidisc

@Suite("Song table sorting")
struct SongTableComparatorTests {
    @Test("Rows keep their list position as their identity, even for a repeated song")
    func rowsAreIdentifiedByPosition() {
        let song = makeSong("a")
        let rows = SongTableRow.rows([song, makeSong("b"), song])
        #expect(rows.map(\.id) == [0, 1, 2])
        #expect(Set(rows.map(\.id)).count == 3)
        #expect(rows[2].song == song)
    }

    @Test("Titles sort like the Finder: ignoring case, with numbers in numeric order")
    func titlesSortNaturally() {
        let rows = SongTableRow.rows([makeSong("1", title: "track 10"), makeSong("2", title: "Track 2"),
                                      makeSong("3", title: "alpha")])
        let sorted = rows.sorted(using: SongTableComparator(column: .title))
        #expect(sorted.map(\.song.id) == ["3", "2", "1"])
        let reversed = rows.sorted(using: SongTableComparator(column: .title, order: .reverse))
        #expect(reversed.map(\.song.id) == ["1", "2", "3"])
    }

    @Test("Songs without an artist sort after named artists")
    func missingArtistSortsLast() {
        let rows = SongTableRow.rows([makeSong("none", artist: nil), makeSong("b", artist: "Bowie"),
                                      makeSong("a", artist: "ABBA")])
        let sorted = rows.sorted(using: SongTableComparator(column: .artist))
        #expect(sorted.map(\.song.id) == ["a", "b", "none"])
    }

    @Test("Sorting by album keeps each album in disc and track order")
    func albumKeepsTrackOrder() {
        let rows = SongTableRow.rows([
            makeSong("b2", album: "B", disc: 1, track: 2),
            makeSong("a-d2t1", album: "A", disc: 2, track: 1),
            makeSong("a-d1t2", album: "A", disc: 1, track: 2),
            makeSong("b1", album: "B", disc: 1, track: 1),
            makeSong("a-d1t1", album: "A", disc: 1, track: 1),
        ])
        let sorted = rows.sorted(using: SongTableComparator(column: .album))
        #expect(sorted.map(\.song.id) == ["a-d1t1", "a-d1t2", "a-d2t1", "b1", "b2"])
    }

    @Test("Equal values keep the list's order in both directions")
    func tiesAreStable() {
        let rows = SongTableRow.rows([makeSong("x", duration: 60), makeSong("y", duration: 60),
                                      makeSong("short", duration: 30)])
        #expect(rows.sorted(using: SongTableComparator(column: .duration)).map(\.song.id) == ["short", "x", "y"])
        #expect(rows.sorted(using: SongTableComparator(column: .duration, order: .reverse)).map(\.song.id)
                == ["x", "y", "short"])
    }

    @Test("The position column restores, or reverses, the list's own order")
    func positionColumn() {
        let rows = SongTableRow.rows([makeSong("c", title: "C"), makeSong("a", title: "A"), makeSong("b", title: "B")])
        let byTitle = rows.sorted(using: SongTableComparator(column: .title))
        #expect(byTitle.sorted(using: SongTableComparator(column: .position)).map(\.song.id) == ["c", "a", "b"])
        #expect(byTitle.sorted(using: SongTableComparator(column: .position, order: .reverse)).map(\.song.id)
                == ["b", "a", "c"])
    }

    private func makeSong(_ id: String, title: String? = nil, artist: String? = "Artist", album: String? = "Album",
                          disc: Int? = nil, track: Int? = nil, duration: TimeInterval = 120) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title ?? id, artist: artist, albumId: nil, albumName: album, artistId: nil, genre: nil,
            duration: duration, discNumber: disc, trackNumber: track, isDownloaded: false, coverArtId: nil,
            audioFormat: nil, replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }
}
