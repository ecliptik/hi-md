import Foundation
import Testing
@testable import Minidisc

@Suite("Widget support", .timeLimit(.minutes(1)))
@MainActor
struct WidgetSupportTests {
    @Test("A widget link opens the matching page, whatever characters the server uses")
    func linksRoundTripIntoDestinations() {
        let album = WidgetSnapshot.Collection(id: "al-1/2 ü", kind: .album, title: "Live & Loud", coverArtId: "al-1")
        #expect(HomeDestination(url: album.url) == .albumById(id: "al-1/2 ü", name: "Live & Loud", subtitle: "", coverArtId: "al-1"))

        let playlist = WidgetSnapshot.Collection(id: "pl-9", kind: .playlist, title: "Road Trip")
        #expect(HomeDestination(url: playlist.url) == .playlistById(id: "pl-9", name: "Road Trip", coverArtId: nil))

        let artist = WidgetSnapshot.Collection(id: "ar-3", kind: .artist, title: "Band")
        #expect(HomeDestination(url: artist.url) == .artistById(id: "ar-3", name: "Band", coverArtId: nil))
    }

    @Test("Other links are ignored")
    func foreignLinksAreIgnored() {
        #expect(HomeDestination(url: URL(string: "https://example.com/album/1")!) == nil)
        #expect(HomeDestination(url: URL(string: "minidisc://song/1")!) == nil)
        #expect(HomeDestination(url: URL(string: "minidisc://album/")!) == nil)
    }

    @Test("The snapshot survives encoding")
    func snapshotRoundTrip() throws {
        let snapshot = WidgetSnapshot(
            hasServer: true,
            nowPlaying: .init(title: "Song", artist: "Artist", artworkFile: "a.jpg", isPlaying: true),
            recentlyPlayed: [.init(id: "1", kind: .album, title: "Album")],
            pinned: [.init(id: "2", kind: .playlist, title: "Playlist", subtitle: "12 songs")],
            moods: [.init(id: "chill", title: "Chill", symbolName: "leaf", isAvailable: true)]
        )
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test("Cover file names are stable and safe")
    func artworkFileNames() {
        let name = WidgetSnapshotStore.artworkFileName(coverArtId: "al-1/../x")
        #expect(name == WidgetSnapshotStore.artworkFileName(coverArtId: "al-1/../x"))
        #expect(name != WidgetSnapshotStore.artworkFileName(coverArtId: "al-2"))
        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".jpg"))
    }

    @Test("Every Mood has a widget counterpart")
    func moodsMatch() {
        #expect(Set(Mood.allCases.map(\.rawValue)) == Set(MinidiscMood.allCases.map(\.rawValue)))
    }

    @Test("A command waits for the app to register its handler")
    func relayWaitsForHandler() async throws {
        let relay = WidgetCommandRelay()
        var received: [WidgetCommand] = []
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            relay.handler = { received.append($0) }
        }
        try await relay.perform(.next)
        #expect(received == [.next])
    }
}
