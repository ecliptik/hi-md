import Foundation
import Testing
@testable import Minidisc

/// A playlist's shown rows mapped back to their positions in the server's order, which
/// Subsonic's `songIndexToRemove` counts in.
@Suite("Playlist row positions")
struct PlaylistRowPositionsTests {
    private static func song(_ id: String, title: String, artist: String? = nil, album: String? = nil) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title, artist: artist, albumId: nil,
            albumName: album, artistId: nil, genre: nil, duration: 180,
            trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    /// Zed, Alpha, Mid, Alpha again (the same song twice), Bravo.
    private static let playlist = [
        song("z", title: "Zed", artist: "Cy"),
        song("a", title: "Alpha", artist: "Ann"),
        song("m", title: "Mid", artist: "Bo"),
        song("a", title: "Alpha", artist: "Ann"),
        song("b", title: "Bravo", artist: "Ann"),
    ]

    @Test func inPlaylistOrderEachRowIsItsOwnPosition() {
        let rows = PlaylistRowPositions(Self.playlist)
        #expect(rows.positions == [0, 1, 2, 3, 4])
        // The second copy of "a", not the first.
        #expect(rows.storedPositions(ofRows: [3]) == [3])
        #expect(rows.storedPositions(ofRows: [1]) == [1])
    }

    @Test func afterASortTheSwipedCopyIsTheOneRemoved() {
        let rows = PlaylistRowPositions(Self.playlist, sortedBy: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        // Alpha, Alpha, Bravo, Mid, Zed: the two Alphas keep their playlist order.
        #expect(rows.rows(of: Self.playlist).map(\.title) == ["Alpha", "Alpha", "Bravo", "Mid", "Zed"])
        #expect(rows.positions == [1, 3, 4, 2, 0])
        #expect(rows.storedPositions(ofRows: [1]) == [3])
        #expect(rows.storedPositions(ofRows: [0]) == [1])
        #expect(rows.storedPositions(ofRows: [4]) == [0])
    }

    @Test func theListsOwnSortsMapBack() {
        let byArtist = PlaylistRowPositions(Self.playlist, sortedBy: PlaylistSortOrder.artist.areInIncreasingOrder)
        // Ann (Alpha, Alpha, Bravo in playlist order), Bo, Cy.
        #expect(byArtist.positions == [1, 3, 4, 2, 0])
        #expect(byArtist.storedPositions(ofRows: [1]) == [3])
        #expect(PlaylistRowPositions(Self.playlist, sortedBy: PlaylistSortOrder.playlistOrder.areInIncreasingOrder).positions
                == [0, 1, 2, 3, 4])
    }

    @Test func afterAFilterRowsSkipTheHiddenSongs() {
        let rows = PlaylistRowPositions(Self.playlist, where: { $0.id != "m" && $0.id != "z" })
        #expect(rows.positions == [1, 3, 4])
        #expect(rows.storedPositions(ofRows: [1]) == [3])
        #expect(rows.storedPositions(ofRows: [2]) == [4])
    }

    @Test func aSortAndAFilterTogether() {
        let rows = PlaylistRowPositions(Self.playlist,
                                        sortedBy: { $0.title.localizedStandardCompare($1.title) == .orderedDescending },
                                        where: { $0.id == "a" || $0.id == "z" })
        // Zed, Alpha, Alpha.
        #expect(rows.positions == [0, 1, 3])
        #expect(rows.storedPositions(ofRows: [2]) == [3])
    }

    @Test func severalRowsComeBackHighestFirstOnce() {
        let rows = PlaylistRowPositions(Self.playlist, sortedBy: { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        #expect(rows.storedPositions(ofRows: [0, 1, 4, 1]) == [3, 1, 0])
        // Rows that aren't there are ignored.
        #expect(rows.storedPositions(ofRows: [7, -1]).isEmpty)
    }
}
