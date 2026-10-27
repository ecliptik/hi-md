import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@MainActor
@Suite("MiniPlayer Library browser")
struct LibraryBrowserModelTests {
    private struct Failure: Error {}

    /// Lists by location; a location missing from `lists` fails.
    private nonisolated final class FakeSource: LibraryBrowserSource, @unchecked Sendable {
        private let lock = NSLock()
        private var lists: [LibraryBrowserLocation: [LibraryBrowserItem]]
        private var requested: [LibraryBrowserLocation] = []

        init(_ lists: [LibraryBrowserLocation: [LibraryBrowserItem]]) {
            self.lists = lists
        }

        var requests: [LibraryBrowserLocation] { lock.withLock { requested } }

        func set(_ items: [LibraryBrowserItem], at location: LibraryBrowserLocation) {
            lock.withLock { lists[location] = items }
        }

        func items(at location: LibraryBrowserLocation) async throws -> [LibraryBrowserItem] {
            let items = lock.withLock { () -> [LibraryBrowserItem]? in
                requested.append(location)
                return lists[location]
            }
            guard let items else { throw Failure() }
            return items
        }
    }

    private static func song(_ id: String, title: String? = nil) -> DisplayableSong {
        DisplayableSong(
            id: id, title: title ?? "Song \(id)", artist: "Artist", albumId: "album", albumName: "Album", artistId: "artist",
            genre: nil, duration: 200, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: "flac",
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil, replayGainAlbumPeak: nil,
            replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    private static let artists = LibraryBrowserItem.artists([
        ArtistID3(id: "abba", name: "ABBA", albumCount: 2),
        ArtistID3(id: "bjork", name: "Björk", albumCount: 9),
        ArtistID3(id: "can", name: "Can", albumCount: 14),
    ])

    private static let bjorkAlbums = LibraryBrowserItem.albums([
        AlbumID3(id: "debut", name: "Debut", songCount: 2, duration: 0, artist: "Björk", artistId: "bjork", year: 1993),
        AlbumID3(id: "post", name: "Post", songCount: 2, duration: 0, artist: "Björk", artistId: "bjork", year: 1995),
    ], newestFirst: true)

    private static let postSongs = LibraryBrowserItem.songs([song("army", title: "Army of Me"), song("hyper", title: "Hyperballad"),
                                                             song("isobel", title: "Isobel")])

    private func makeModel(_ extra: [LibraryBrowserLocation: [LibraryBrowserItem]] = [:]) -> (LibraryBrowserModel, FakeSource) {
        var lists: [LibraryBrowserLocation: [LibraryBrowserItem]] = [
            .artists: Self.artists,
            .artist(id: "bjork", name: "Björk"): Self.bjorkAlbums,
            .album(id: "post", name: "Post"): Self.postSongs,
        ]
        lists.merge(extra) { $1 }
        let source = FakeSource(lists)
        return (LibraryBrowserModel(source: source, searchDelay: .zero), source)
    }

    // MARK: Drilling down

    @Test func homeListsArtistsPlaylistsAndFavorites() {
        let (model, _) = makeModel()
        #expect(model.location == .home)
        #expect(!model.canGoBack)
        #expect(model.rows.map(\.destination) == [.artists, .playlists, .favorites])
    }

    @Test func drillsFromArtistsToAlbumsToSongsAndBack() async {
        let (model, source) = makeModel()
        model.open(model.rows[0])
        #expect(model.phase == .loading)
        await model.waitForLoads()
        #expect(model.location == .artists)
        #expect(model.rows.map(\.name) == ["ABBA", "Björk", "Can"])

        model.open(model.rows[1])
        await model.waitForLoads()
        #expect(model.location == .artist(id: "bjork", name: "Björk"))
        // Newest first.
        #expect(model.rows.map(\.name) == ["Post", "Debut"])

        model.open(model.rows[0])
        await model.waitForLoads()
        #expect(model.rows.map(\.name) == ["Army of Me", "Hyperballad", "Isobel"])
        #expect(model.previousLocation == .artist(id: "bjork", name: "Björk"))

        // A song has nowhere to go.
        model.open(model.rows[0])
        #expect(model.pages.count == 4)

        // Back returns to each list as it was, without loading it again.
        model.goBack()
        #expect(model.rows.map(\.name) == ["Post", "Debut"])
        model.goBack()
        #expect(model.rows.map(\.name) == ["ABBA", "Björk", "Can"])
        #expect(source.requests == [.artists, .artist(id: "bjork", name: "Björk"), .album(id: "post", name: "Post")])
        model.goHome()
        #expect(model.location == .home)
        model.goBack()
        #expect(model.location == .home)
    }

    @Test func eachListHasItsOwnSearch() async {
        let (model, _) = makeModel()
        model.open(.artists)
        await model.waitForLoads()
        // Winamp's search: case and accents don't matter.
        model.query = "bjo"
        #expect(model.rows.map(\.name) == ["Björk"])
        model.open(model.rows[0])
        await model.waitForLoads()
        // A list opened starts unfiltered.
        #expect(model.query.isEmpty)
        model.query = "zzz"
        #expect(model.rows.isEmpty)
        #expect(model.hasNoMatches)
        model.goBack()
        #expect(model.query == "bjo")
        #expect(model.rows.map(\.name) == ["Björk"])
        #expect(!model.hasNoMatches)
    }

    @Test func aSongPlaysTheListAsTheSearchLeavesIt() async {
        let (model, _) = makeModel()
        model.open(.album(id: "post", name: "Post"))
        await model.waitForLoads()
        let isobel = model.rows[2]
        #expect(model.songsToPlay(startingAt: isobel)?.index == 2)
        #expect(model.songsToPlay(startingAt: isobel)?.songs.map(\.id) == ["army", "hyper", "isobel"])
        model.query = "y"
        #expect(model.rows.map(\.name) == ["Army of Me", "Hyperballad"])
        let hyper = model.rows[1]
        #expect(model.songsToPlay(startingAt: hyper)?.index == 1)
        #expect(model.songsToPlay(startingAt: hyper)?.songs.map(\.id) == ["army", "hyper"])
        // A row the search hides doesn't play.
        #expect(model.songsToPlay(startingAt: isobel) == nil)
    }

    @Test func aFailedListCanBeRetried() async {
        let (model, source) = makeModel()
        model.open(.playlists)
        await model.waitForLoads()
        guard case .failed = model.phase else {
            Issue.record("Expected the list to fail, got \(model.phase)")
            return
        }
        let playlist = Playlist(id: "p1", name: "Road Trip", songCount: 12, duration: 3_000)
        source.set(LibraryBrowserItem.playlists([playlist]), at: .playlists)
        model.reload()
        await model.waitForLoads()
        #expect(model.phase == .loaded)
        #expect(model.rows.map(\.destination) == [.playlist(id: "p1", name: "Road Trip")])
    }

    @Test func leavingAListStopsItsLoad() async {
        let (model, _) = makeModel()
        model.open(.artists)
        model.goBack()
        await model.waitForLoads()
        #expect(model.location == .home)
        #expect(model.pages.count == 1)
    }

    // MARK: Searching the library

    @Test func theHomeSearchSearchesTheLibrary() async {
        let results = LibraryBrowserItem.grouped(
            artists: [ArtistID3(id: "bjork", name: "Björk")],
            albums: [AlbumID3(id: "post", name: "Post", songCount: 11, duration: 0, artist: "Björk", artistId: "bjork")],
            songs: [Self.song("army", title: "Army of Me")]
        )
        let (model, source) = makeModel([.search("bjork"): results])
        model.query = "  bjork "
        #expect(model.isSearchingLibrary)
        await model.waitForLoads()
        #expect(source.requests == [.search("bjork")])
        #expect(model.rows.map(\.group) == [.artists, .albums, .songs])
        #expect(model.songsToPlay(startingAt: model.rows[2])?.songs.map(\.id) == ["army"])
        // Opening a result leaves the search on the home page.
        model.open(model.rows[0])
        await model.waitForLoads()
        #expect(model.location == .artist(id: "bjork", name: "Björk"))
        model.goBack()
        #expect(model.query == "  bjork ")
        #expect(model.rows.count == 3)
        // Clearing the field brings the lists back.
        model.query = ""
        #expect(!model.isSearchingLibrary)
        #expect(model.rows.map(\.destination) == [.artists, .playlists, .favorites])
    }

    @Test func aSearchWithNoResultsSaysSo() async {
        let (model, _) = makeModel([.search("zzz"): []])
        model.query = "zzz"
        await model.waitForLoads()
        #expect(model.rows.isEmpty)
        #expect(model.hasNoMatches)
    }

    @Test func resetGoesHomeAndForgetsTheSearch() async {
        let (model, _) = makeModel([.search("can"): []])
        model.query = "can"
        await model.waitForLoads()
        model.open(.artists)
        await model.waitForLoads()
        model.reset()
        #expect(model.location == .home)
        #expect(model.query.isEmpty)
        #expect(model.searchPage == nil)
    }

    // MARK: Rows from the server

    @Test func rowsCarryWhatTheyOpenAndPlay() {
        let album = LibraryBrowserItem.albums([AlbumID3(id: "a", name: "Gold", songCount: 1, duration: 0, coverArt: "al-a")])[0]
        #expect(album.destination == .album(id: "a", name: "Gold"))
        #expect(album.coverArtID == "al-a")
        #expect(album.song == nil)
        // A song twice in a playlist gets two rows.
        let songs = LibraryBrowserItem.songs([Self.song("x"), Self.song("x")])
        #expect(Set(songs.map(\.id)).count == 2)
        #expect(songs.allSatisfy { $0.destination == nil && $0.song?.id == "x" })
        // Albums without a year go last.
        let ordered = LibraryBrowserItem.albums([
            AlbumID3(id: "1", name: "B", songCount: 0, duration: 0),
            AlbumID3(id: "2", name: "Old", songCount: 0, duration: 0, year: 1990),
            AlbumID3(id: "3", name: "A", songCount: 0, duration: 0),
            AlbumID3(id: "4", name: "New", songCount: 0, duration: 0, year: 2020),
        ], newestFirst: true)
        #expect(ordered.map(\.name) == ["New", "Old", "A", "B"])
    }
}
