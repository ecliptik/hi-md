import Foundation
import Testing
@testable import Minidisc

@Suite("Autoplay settings")
@MainActor
struct AutoplaySettingsTests {
    private func song(_ id: String, album: String?) -> DisplayableSong {
        DisplayableSong(
            id: id, title: id, artist: nil, albumId: album, albumName: nil, artistId: nil, genre: nil,
            duration: 200, trackNumber: nil, isDownloaded: false, coverArtId: nil, audioFormat: nil,
            replayGainTrackGain: nil, replayGainTrackPeak: nil, replayGainAlbumGain: nil,
            replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    @Test("An album is two or more songs from one album")
    func singleAlbum() {
        #expect(AutoplayAlbumDirection.isSingleAlbum([song("1", album: "a"), song("2", album: "a")]))
        #expect(!AutoplayAlbumDirection.isSingleAlbum([song("1", album: "a"), song("2", album: "b")]))
        #expect(!AutoplayAlbumDirection.isSingleAlbum([song("1", album: "a")]))
        #expect(!AutoplayAlbumDirection.isSingleAlbum([song("1", album: nil), song("2", album: nil)]))
        #expect(!AutoplayAlbumDirection.isSingleAlbum([]))
    }

    @Test("Stop After the Album holds back Autoplay only for albums")
    func albumDirection() {
        let album = [song("1", album: "a"), song("2", album: "a")]
        let playlist = [song("1", album: "a"), song("2", album: "b")]
        #expect(AutoplayAlbumDirection.similar.allowsExtending(requested: album))
        #expect(!AutoplayAlbumDirection.stop.allowsExtending(requested: album))
        #expect(AutoplayAlbumDirection.stop.allowsExtending(requested: playlist))
    }

    @Test("Preferences default to similar music, counted as plays, and read what the page stores")
    func preferences() throws {
        let defaults = try #require(UserDefaults(suiteName: "autoplay.\(UUID())"))
        let preferences = PlaybackPreferences(defaults: defaults)
        #expect(preferences.autoplayAlbumDirection == .similar)
        #expect(preferences.autoplayCountsAsPlays)
        defaults.set(AutoplayAlbumDirection.stop.rawValue, forKey: PlaybackPreferences.Key.autoplayAlbumDirection)
        defaults.set(false, forKey: PlaybackPreferences.Key.autoplayCountsAsPlays)
        #expect(preferences.autoplayAlbumDirection == .stop)
        #expect(!preferences.autoplayCountsAsPlays)
    }

    @Test("Only songs past the requested queue count as autoplayed")
    func autoplayedTrack() {
        let state = PlayerState()
        state.queue = [song("1", album: "a"), song("2", album: "a"), song("3", album: "b")]
        state.currentIndex = 1
        #expect(!state.isPlayingAutoplayedTrack)
        state.originalQueueEndIndex = 2
        #expect(!state.isPlayingAutoplayedTrack)
        state.currentIndex = 2
        #expect(state.isPlayingAutoplayedTrack)
    }
}
