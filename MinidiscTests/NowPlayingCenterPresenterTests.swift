#if os(iOS) && canImport(NowPlaying)
import AppIntents
import Foundation
import NowPlaying
import Testing
import UIKit
@testable import Minidisc

@Suite("Now Playing session model")
@MainActor
struct NowPlayingCenterPresenterTests {
    private func snapshot(_ songId: String?, title: String, position: TimeInterval = 0, rate: Float = 1,
                          duration: TimeInterval = 200, live: Bool = false) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: title, artist: "Artist", album: "Album", duration: duration, position: position,
                           playbackRate: rate, artworkURL: nil, artworkHeaders: [:], coverArtId: songId.map { "cover-\($0)" },
                           isLiveStream: live, radioStationName: live ? "Station" : nil, songId: songId)
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    @Test("A song becomes music content tied to its Siri entity")
    func songContent() throws {
        let presenter = NowPlayingCenterPresenter()
        presenter.entityScope = { String(repeating: "a", count: 64) }
        presenter.setBaseInfo(for: snapshot("s1", title: "First"), generation: 1)

        let content = try #require(presenter.model.content as? MusicContent)
        #expect(content.songTitle == "First")
        #expect(content.artistName == "Artist")
        if case .finite(let seconds)? = content.duration { #expect(seconds == 200) } else { Issue.record("Expected a finite duration") }
        let expected = MusicIntentID(scope: String(repeating: "a", count: 64), kind: .song, resourceID: "s1").rawValue
        #expect(content.appEntityIdentifiers.map(\.identifier) == [expected])
    }

    @Test("Local files have no Siri entity")
    func localFileHasNoEntity() throws {
        let presenter = NowPlayingCenterPresenter()
        presenter.entityScope = { String(repeating: "a", count: 64) }
        presenter.setBaseInfo(for: snapshot("local:abc", title: "Local"), generation: 1)
        let content = try #require(presenter.model.content as? MusicContent)
        #expect(content.appEntityIdentifiers.isEmpty)
    }

    @Test("The next song on the same album keeps its cover, under its own artwork identity")
    func sameAlbumKeepsCoverThroughTheChange() throws {
        let presenter = NowPlayingCenterPresenter()
        func albumSong(_ id: String) -> NowPlayingSnapshot {
            NowPlayingSnapshot(title: id, artist: "Artist", album: "Album", duration: 200, position: 0,
                               playbackRate: 1, artworkURL: nil, artworkHeaders: [:], coverArtId: "album-cover",
                               isLiveStream: false, radioStationName: nil, songId: id)
        }
        presenter.setBaseInfo(for: albumSong("t1"), generation: 1)
        presenter.setArtwork(image: image(), fallback: albumSong("t1"), generation: 1)
        let first = try #require(presenter.model.content as? MusicContent)
        let firstArtwork = try #require(first.artwork)

        presenter.setBaseInfo(for: albumSong("t2"), generation: 2)
        let second = try #require(presenter.model.content as? MusicContent)
        let secondArtwork = try #require(second.artwork)
        #expect(second.songTitle == "t2")
        #expect(secondArtwork.id != firstArtwork.id)
    }

    @Test("Late artwork for the previous track never lands on the next one")
    func crossfadeHandOffKeepsArtworkWithItsTrack() throws {
        let presenter = NowPlayingCenterPresenter()
        presenter.setBaseInfo(for: snapshot("a", title: "Outgoing"), generation: 1)
        // The incoming deck becomes current before the outgoing track's artwork finishes loading.
        presenter.setBaseInfo(for: snapshot("b", title: "Incoming"), generation: 2)
        presenter.setArtwork(image: image(), fallback: snapshot("a", title: "Outgoing"), generation: 1)

        let content = try #require(presenter.model.content as? MusicContent)
        #expect(content.songTitle == "Incoming")
        #expect(content.artwork == nil)

        presenter.setArtwork(image: image(), fallback: snapshot("b", title: "Incoming"), generation: 2)
        #expect((presenter.model.content as? MusicContent)?.artwork?.id.hasPrefix("b#cover-b#") == true)
    }

    @Test("A cover already in memory goes out with the song, and a sharper one replaces it as new artwork")
    func coverGoesOutWithTheSong() throws {
        let presenter = NowPlayingCenterPresenter()
        presenter.setBaseInfo(for: snapshot("s1", title: "Song"), artwork: image(), generation: 1)
        let thumbnail = try #require((presenter.model.content as? MusicContent)?.artwork)
        presenter.setArtwork(image: image(), fallback: snapshot("s1", title: "Song"), generation: 1)
        let fullSize = try #require((presenter.model.content as? MusicContent)?.artwork)
        #expect(fullSize.id != thumbnail.id)
    }

    @Test("Position updates move the clock without replacing the song")
    func positionUpdates() throws {
        let presenter = NowPlayingCenterPresenter()
        presenter.setBaseInfo(for: snapshot("s1", title: "Song"), generation: 1)
        presenter.mergePosition(elapsed: 42, rate: 0, duration: 200, generation: 1)
        // MediaPlaybackSnapshot exposes no fields; its state and time are only visible to the system.
        #expect(presenter.model.playbackSnapshot != nil)
        #expect((presenter.model.content as? MusicContent)?.songTitle == "Song")

        presenter.mergePosition(elapsed: 50, rate: 1, duration: 200, generation: 0)
        #expect((presenter.model.content as? MusicContent)?.songTitle == "Song")
    }

    @Test("Radio is shown as a live station")
    func radioContent() throws {
        let presenter = NowPlayingCenterPresenter()
        presenter.setBaseInfo(for: snapshot(nil, title: "Live show", live: true), generation: 1)
        let content = try #require(presenter.model.content as? RadioContent)
        #expect(content.stationName == "Station")
    }

    @Test("Clearing removes the content")
    func clearing() {
        let presenter = NowPlayingCenterPresenter()
        presenter.setBaseInfo(for: snapshot("s1", title: "Song"), generation: 1)
        presenter.clear(generation: 2)
        #expect(presenter.model.content == nil)
        #expect(presenter.model.playbackSnapshot == nil)
    }
}
#endif
