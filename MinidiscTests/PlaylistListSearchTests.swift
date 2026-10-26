import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

private actor PlaylistListSource: PlaylistBrowsing, RecentlyAddedAlbumBrowsing, StarredBrowsing {
    func playlists() async throws -> [Playlist] { [] }
    func playlist(id: String) async throws -> PlaylistWithSongs { throw URLError(.unsupportedURL) }
    func recentlyAddedAlbums(size: Int) async throws -> [AlbumID3] { [] }
    func getStarred2() async throws -> Starred2 { throw URLError(.unsupportedURL) }
}

@MainActor
@Suite("Playlists tab search")
struct PlaylistListSearchTests {
    private let playlists = [
        Playlist(id: "energetic", name: "Minidisc · Énergique", songCount: 75, duration: 18_000, owner: "alex"),
        Playlist(id: "road", name: "Road Trip", songCount: 20, duration: 4_800, comment: "Long drives", owner: "alex"),
        Playlist(id: "jazz", name: "Late Night Jazz", songCount: 12, duration: 3_000, comment: "Smoky clubs", owner: "sam"),
        Playlist(id: "workout", name: "Workout Mix", songCount: 30, duration: 6_000, owner: "alex"),
    ]

    private func ids(_ query: String) -> [String] {
        PlaylistListViewModel.filter(playlists, matching: query).map(\.id)
    }

    @Test("an empty or blank query keeps every playlist in server order")
    func emptyQueryKeepsAll() {
        #expect(ids("") == ["energetic", "road", "jazz", "workout"])
        #expect(ids("   ") == ["energetic", "road", "jazz", "workout"])
    }

    @Test("names match ignoring case, accents and punctuation")
    func matchesFoldedName() {
        #expect(ids("energ") == ["energetic"])
        #expect(ids("MINIDISC") == ["energetic"])
        #expect(ids("night") == ["jazz"])
    }

    @Test("every word must match, in any order and across fields")
    func everyWordMustMatch() {
        #expect(ids("jazz late") == ["jazz"])
        #expect(ids("road sam") == [])
        #expect(ids("jazz smoky") == ["jazz"])
    }

    @Test("the comment also matches, the owner doesn't")
    func matchesCommentNotOwner() {
        #expect(ids("drives") == ["road"])
        #expect(ids("alex").isEmpty)
        #expect(ids("alex").isEmpty)
    }

    @Test("an unmatched query returns nothing")
    func unmatchedQuery() {
        #expect(ids("zzz").isEmpty)
    }

    @Test("derived playlists match on the title they show")
    func derivedRowsMatchTheirTitle() throws {
        let vm = PlaylistListViewModel(libraryService: PlaylistListSource())
        vm.bestOfPlaylists = [
            ArtistBestOf(artistId: "aphex", artistName: "Aphex Twin", coverArtId: nil, songs: []),
            ArtistBestOf(artistId: "bush", artistName: "Kate Bush", coverArtId: nil, songs: []),
        ]
        vm.newestAlbum = try JSONDecoder().decode(
            AlbumID3.self, from: Data(#"{"id":"a","name":"Album","songCount":1,"duration":100}"#.utf8)
        )

        #expect(vm.bestOfPlaylists(matching: "").map(\.artistId) == ["aphex", "bush"])
        #expect(vm.bestOfPlaylists(matching: "aphex").map(\.artistId) == ["aphex"])
        #expect(vm.bestOfPlaylists(matching: "best of").count == 2)
        #expect(vm.newestAlbum(matching: "")?.id == "a")
        #expect(vm.newestAlbum(matching: "recently")?.id == "a")
        #expect(vm.newestAlbum(matching: "aphex") == nil)
    }
}
