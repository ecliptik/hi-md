import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Home feed layout")
@MainActor
struct HomeFeedLayoutTests {
    private func album(_ id: String) -> AlbumID3 {
        AlbumID3(id: id, name: id, songCount: 1, duration: 180)
    }

    private func layout(
        isOnline: Bool = true,
        isLoading: Bool = false,
        isEmpty: Bool = false,
        error: UserFacingError? = nil,
        hasPartialFailure: Bool = false,
        pending: Set<HomeFeedViewModel.Section> = [],
        content: HomeFeedContent = HomeFeedContent()
    ) -> HomeFeedState {
        HomeFeedLayout.state(isOnline: isOnline, isLoading: isLoading, isEmpty: isEmpty, error: error,
                             hasPartialFailure: hasPartialFailure, pending: pending, content: content)
    }

    private func rowIDs(_ state: HomeFeedState) -> [String]? {
        guard case .rows(let rows) = state else { return nil }
        return rows.map(\.id)
    }

    @Test("Shelves follow the iPhone's order and empty ones are left out")
    func order() {
        let content = HomeFeedContent(
            playlists: [Playlist(id: "p", name: "Mix", songCount: 1, duration: 60)],
            favorites: HomeFavorites(songs: [Song(id: "s", title: "Song")], albums: [album("fav")]),
            recentlyPlayed: [album("recent")],
            heavyRotation: [album("heavy")],
            rediscovery: [],
            relevantAdditions: [album("relevant")],
            otherAdditions: [album("added")],
            genres: [.init(name: "Jazz", albums: [album("jazz")]), .init(name: "Rock", albums: [album("rock")])]
        )
        #expect(rowIDs(layout(content: content)) == [
            "playlists", "favoriteSongs", "favoriteAlbums", "recentlyPlayed", "heavyRotation",
            "relevantAdditions", "recentlyAdded", "genre.Jazz", "genre.Rock",
        ])
    }

    @Test("A loading section holds its place only online and only while it is empty")
    func placeholders() {
        let pending: Set<HomeFeedViewModel.Section> = [.playlists, .history, .recent]
        #expect(rowIDs(layout(isLoading: true, pending: pending)) == [
            "placeholder.playlists", "placeholder.recentlyPlayed", "placeholder.recentlyAdded",
        ])
        let arrived = HomeFeedContent(recentlyPlayed: [album("recent")], relevantAdditions: [album("relevant")])
        #expect(rowIDs(layout(isLoading: true, pending: pending, content: arrived)) == [
            "placeholder.playlists", "recentlyPlayed", "relevantAdditions",
        ])
        #expect(layout(isOnline: false, isLoading: true, pending: pending).isRows(["offline"]))
    }

    @Test("Loading with nothing to hold a place for shows the spinner")
    func spinner() {
        #expect(layout(isLoading: true, isEmpty: true).isLoading)
    }

    @Test("An empty feed is an error, an empty library or, offline, the music on this device")
    func fullPageStates() {
        #expect(layout(isEmpty: true, error: .noNetwork).isFailed)
        #expect(layout(isEmpty: true).isEmpty)
        let device = HomeFeedContent(favorites: HomeFavorites(songs: [Song(id: "s", title: "Song")]),
                                     offlineAlbums: [album("saved")])
        #expect(rowIDs(layout(isOnline: false, isEmpty: true, content: device)) == ["offline", "favoriteSongs", "offlineAlbums"])
        // Offline, an error is not shown: the device's music is.
        #expect(layout(isOnline: false, isEmpty: true, error: .noNetwork).isRows(["offline"]))
    }

    @Test("The offline card replaces the partial-failure notice")
    func notices() {
        let content = HomeFeedContent(recentlyPlayed: [album("recent")])
        #expect(rowIDs(layout(hasPartialFailure: true, content: content)) == ["partialFailure", "recentlyPlayed"])
        #expect(rowIDs(layout(isOnline: false, hasPartialFailure: true, content: content)) == ["offline", "recentlyPlayed"])
    }

    @Test("A shelf's See All page lists that shelf's albums")
    func seeAll() {
        let content = HomeFeedContent(favorites: HomeFavorites(albums: [album("fav")]), otherAdditions: [album("added")],
                                      genres: [.init(name: "Jazz", albums: [album("jazz")])])
        #expect(HomeFeedLayout.albums(for: .favoriteAlbums, in: content).map(\.id) == ["fav"])
        #expect(HomeFeedLayout.albums(for: .recentlyAdded, in: content).map(\.id) == ["added"])
        #expect(HomeFeedLayout.albums(for: .genre("Jazz"), in: content).map(\.id) == ["jazz"])
        #expect(HomeFeedLayout.albums(for: .genre("Blues"), in: content).isEmpty)
    }

    @Test("A genre keeps the server's name as its title")
    func genreTitle() {
        #expect(HomeShelf.genre("Musique Concrète").title == "Musique Concrète")
    }
}

private extension HomeFeedState {
    var isLoading: Bool { if case .loading = self { true } else { false } }
    var isFailed: Bool { if case .failed = self { true } else { false } }
    var isEmpty: Bool { if case .empty = self { true } else { false } }
    func isRows(_ ids: [String]) -> Bool {
        if case .rows(let rows) = self { rows.map(\.id) == ids } else { false }
    }
}
