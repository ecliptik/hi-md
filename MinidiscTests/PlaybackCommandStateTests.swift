import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Mac playback commands")
@MainActor
struct PlaybackCommandStateTests {
    // MARK: - Space bar

    private let idle = PlaybackKeyRouting.Context(isEditingText: false, isMainWindowFocused: true, canTogglePlayback: true)

    @Test("A plain space in the main window toggles playback")
    func spaceTogglesPlayback() {
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true), in: idle) == .togglePlayback)
    }

    @Test("A space typed into a text field or search field stays with the field")
    func spaceInTextFieldIsTyped() {
        var editing = idle
        editing.isEditingText = true
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true), in: editing) == .passThrough)
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true, isRepeat: true), in: editing) == .passThrough)
    }

    @Test("Sheets, alerts and other windows keep the space bar for their buttons")
    func spaceOutsideMainWindowPassesThrough() {
        var sheet = idle
        sheet.isMainWindowFocused = false
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true), in: sheet) == .passThrough)
    }

    @Test("Space with a modifier, other keys, or nothing to play pass through")
    func otherKeysPassThrough() {
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true, hasModifiers: true), in: idle) == .passThrough)
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: false), in: idle) == .passThrough)
        var empty = idle
        empty.canTogglePlayback = false
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true), in: empty) == .passThrough)
    }

    @Test("Holding the space bar toggles once and ignores the repeats")
    func heldSpaceTogglesOnce() {
        #expect(PlaybackKeyRouting.decision(for: .init(isSpace: true, isRepeat: true), in: idle) == .ignore)
    }

    // MARK: - Command enabling

    @Test("With nothing loaded, only the commands that need no song are off")
    func nothingLoaded() {
        let state = PlaybackCommandState(playerState: PlayerState())
        #expect(!state.canTogglePlayback)
        #expect(!state.canSkip)
        #expect(!state.canShuffle)
        #expect(!state.canRepeat)
        #expect(!state.canGoToCurrentSong)
        #expect(!state.canShowLyrics)
    }

    @Test("A playing album enables every command")
    func playingQueue() throws {
        let playerState = PlayerState()
        playerState.queue = try [song("a", albumID: "al"), song("b", albumID: "al")]
        playerState.currentTrack = playerState.queue[0]
        let state = PlaybackCommandState(playerState: playerState)
        #expect(state.canTogglePlayback)
        #expect(state.canSkip)
        #expect(state.canShuffle)
        #expect(state.canRepeat)
        #expect(state.canGoToCurrentSong)
        #expect(state.canShowLyrics)
    }

    @Test("One song can't be shuffled, and a song without an album can't be revealed")
    func singleSongWithoutAlbum() throws {
        let playerState = PlayerState()
        playerState.queue = try [song("a", albumID: nil)]
        playerState.currentTrack = playerState.queue[0]
        let state = PlaybackCommandState(playerState: playerState)
        #expect(!state.canShuffle)
        #expect(state.canSkip)
        #expect(!state.canGoToCurrentSong)
    }

    @Test("A radio stream only plays and pauses")
    func liveStream() {
        let state = PlaybackCommandState(hasTrack: false, queueCount: 3, isLiveStream: true, hasAlbum: false, isLocalFile: false)
        #expect(state.canTogglePlayback)
        #expect(!state.canSkip)
        #expect(!state.canShuffle)
        #expect(!state.canRepeat)
        #expect(!state.canShowLyrics)
    }

    @Test("A local file has no server album or lyrics")
    func localFile() {
        let state = PlaybackCommandState(hasTrack: true, queueCount: 1, isLiveStream: false, hasAlbum: true, isLocalFile: true)
        #expect(!state.canGoToCurrentSong)
        #expect(!state.canShowLyrics)
        #expect(state.canTogglePlayback)
    }

    // MARK: - Volume

    @Test("Volume steps by a tenth, lands on even values and stays within range")
    func volumeSteps() {
        #expect(PlaybackVolume.adjusted(0.5, steps: 1) == 0.6)
        #expect(PlaybackVolume.adjusted(0.73, steps: -1) == 0.6)
        #expect(PlaybackVolume.adjusted(0.95, steps: 1) == 1)
        #expect(PlaybackVolume.adjusted(1, steps: 1) == 1)
        #expect(PlaybackVolume.adjusted(0.04, steps: -1) == 0)
        #expect(PlaybackVolume.adjusted(0, steps: -3) == 0)
    }

    private func song(_ id: String, albumID: String?) throws -> DisplayableSong {
        var json: [String: Any] = ["id": id, "title": id, "isDir": false]
        if let albumID { json["albumId"] = albumID }
        let data = try JSONSerialization.data(withJSONObject: json)
        return DisplayableSong(from: try JSONDecoder().decode(Song.self, from: data))
    }
}
