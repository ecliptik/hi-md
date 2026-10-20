import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Spotlight and open links")
@MainActor
struct SpotlightIndexerTests {
    private let scope = MusicIntentID.scope(baseURL: "https://music.example", username: "alice")

    @Test func openLinksReachTheItemScreen() throws {
        let album = MusicIntentID(scope: scope, kind: .album, resourceID: "al/1 é")
        let url = try #require(LinkRouter.url(for: album, name: "Blue & Gold"))
        guard case .albumById(let id, let name, _, _) = HomeDestination(url: url) else {
            Issue.record("Expected an album destination from \(url)")
            return
        }
        #expect(id == "al/1 é")
        #expect(name == "Blue & Gold")
        #expect(LinkRouter.url(for: MusicIntentID(scope: scope, kind: .song, resourceID: "s"), name: "Song") == nil)
    }

    @Test func routerHoldsALinkUntilTaken() throws {
        let router = LinkRouter()
        let url = try #require(URL(string: "minidisc://playlist/p1?name=Road%20Trip"))
        router.open(url)
        #expect(router.pending == url)
        #expect(router.take() == url)
        #expect(router.pending == nil)
        #expect(router.take() == nil)
    }

    @Test func fingerprintFollowsNamesAndMembership() {
        let a = MusicIntentRecord(scope: scope, album: AlbumID3(id: "a", name: "First", songCount: 1, duration: 60))
        let b = MusicIntentRecord(scope: scope, artist: ArtistID3(id: "b", name: "Band"))
        let renamed = MusicIntentRecord(scope: scope, album: AlbumID3(id: "a", name: "First (Remaster)", songCount: 1, duration: 60))
        let base = SpotlightIndexer.fingerprint(of: [a, b])
        #expect(base == SpotlightIndexer.fingerprint(of: [a, b]))
        #expect(base != SpotlightIndexer.fingerprint(of: [a]))
        #expect(base != SpotlightIndexer.fingerprint(of: [renamed, b]))
    }
}
