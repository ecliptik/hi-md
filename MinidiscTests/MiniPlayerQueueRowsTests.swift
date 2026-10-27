import Foundation
import Testing
@testable import Minidisc

@Suite("Mac MiniPlayer queue rows")
struct MiniPlayerQueueRowsTests {
    private func song(_ id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Song \(id)", artist: "Artist", albumId: "album", albumName: "Album", artistId: "artist",
            genre: nil, duration: 200, trackNumber: nil, isDownloaded: false, coverArtId: "al-album", audioFormat: "flac",
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private let queue = ["a", "b", "c", "d", "e", "f"]

    private func items(current: Int, autoplayStart: Int? = nil, isPlaying: Bool = true) -> [MiniPlayerQueueRows.Item] {
        MiniPlayerQueueRows.items(queue: queue.map(song), currentIndex: current, isPlaying: isPlaying,
                                  autoplayStart: autoplayStart)
    }

    /// The list as text: headings in capitals, songs as id and role.
    private func outline(_ items: [MiniPlayerQueueRows.Item]) -> [String] {
        items.map { item in
            switch item {
            case .heading(let heading): heading.rawValue.uppercased()
            case .song(let row): "\(row.song.id):\(row.role)"
            }
        }
    }

    private func songIDs(_ items: [MiniPlayerQueueRows.Item]) -> [MiniPlayerQueueRows.Item.ID] {
        items.compactMap { item -> MiniPlayerQueueRows.Item.ID? in
            if case .song = item { return item.id }
            return nil
        }
    }

    @Test func theListRunsInQueueOrderUnderItsHeadings() {
        #expect(outline(items(current: 2)) == [
            "BACKTO", "a:history", "b:history",
            "NOWPLAYING", "c:current",
            "d:requested", "e:requested", "f:requested",
        ])
        // Autoplay's songs follow the listener's under their own heading.
        #expect(outline(items(current: 0, autoplayStart: 4)) == [
            "NOWPLAYING", "a:current",
            "PLAYINGNEXT", "b:requested", "c:requested", "d:requested",
            "CONTINUEPLAYING", "e:autoplay", "f:autoplay",
        ])
    }

    @Test func clickingASongFurtherDownKeepsEveryRowAndOnlyMovesTheHeadings() {
        let before = items(current: 1)
        let after = items(current: 4)
        // The same songs in the same order, each with the same identity: no row is rebuilt.
        #expect(songIDs(before) == songIDs(after))
        #expect(outline(after) == [
            "BACKTO", "a:history", "b:history", "c:history", "d:history",
            "NOWPLAYING", "e:current", "f:requested",
        ])
        // The headings keep their identity too, so the list can find Now Playing to scroll to.
        #expect(after.contains { $0.id == .heading(.nowPlaying) })
    }

    @Test func theCurrentSongIsTheQueuesAtTheCurrentIndex() {
        // Right after a jump the index has moved before the player has the new song: the list
        // already shows the song it's going to, and not the old one twice.
        let rows = items(current: 3)
        let current = rows.compactMap { item -> MiniPlayerQueueRows.Song? in
            if case .song(let row) = item, row.role == .current { return row }
            return nil
        }
        #expect(current.map(\.song.id) == ["d"])
        #expect(current.first?.index == 3)
        #expect(Set(songIDs(rows)).count == queue.count)
    }

    @Test func aSongQueuedTwiceHasTwoRows() {
        let rows = MiniPlayerQueueRows.items(queue: ["a", "b", "a", "c"].map(song), currentIndex: 1, isPlaying: true,
                                             autoplayStart: nil)
        let ids = songIDs(rows)
        #expect(ids == [.song("a", occurrence: 0), .song("b", occurrence: 0), .song("a", occurrence: 1),
                        .song("c", occurrence: 0)])
    }

    @Test func upcomingSongsKnowTheirPlaceInUpNext() {
        let positions = items(current: 1, autoplayStart: 4).compactMap { item -> Int? in
            if case .song(let row) = item { return row.upcomingPosition }
            return nil
        }
        #expect(positions == [0, 1, 2, 3])
        #expect(MiniPlayerQueueRows.hasUpcoming(items(current: 1)))
        #expect(!MiniPlayerQueueRows.hasUpcoming(items(current: 5)))
    }

    @Test func withNothingPlayingThereIsNoCurrentRow() {
        #expect(outline(items(current: 2, isPlaying: false)) == [
            "BACKTO", "a:history", "b:history", "d:requested", "e:requested", "f:requested",
        ])
        #expect(MiniPlayerQueueRows.items(queue: [], currentIndex: 0, isPlaying: true, autoplayStart: nil).isEmpty)
    }

    @Test func theHistoryKeepsTheMostRecentSongs() {
        let rows = MiniPlayerQueueRows.items(queue: queue.map(song), currentIndex: 5, isPlaying: true,
                                             autoplayStart: nil, historyLimit: 2)
        #expect(outline(rows) == ["BACKTO", "d:history", "e:history", "NOWPLAYING", "f:current"])
    }
}
