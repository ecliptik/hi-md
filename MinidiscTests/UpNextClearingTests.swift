import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Clearing Up Next")
@MainActor
struct UpNextClearingTests {
    @Test("Clearing removes every later song and keeps the current one playing")
    func clearsUpcomingSongs() async throws {
        let player = UpNextPlayerStub(state: try makeState(["a", "b", "c", "d"], current: 1))
        let removed = await UpNextClearing.clear(player: player, state: player.state)
        #expect(removed == 2)
        #expect(player.state.queue.map(\.id) == ["a", "b"])
        #expect(player.state.currentIndex == 1)
        #expect(player.state.currentTrack?.id == "b")
        #expect(player.state.position == 42)
        #expect(player.state.playbackState == .playing)
    }

    @Test("Songs are removed from the end, so the next song changes only at the last step")
    func removesFromTheEnd() async throws {
        let player = UpNextPlayerStub(state: try makeState(["a", "b", "c", "d"], current: 0))
        await UpNextClearing.clear(player: player, state: player.state)
        #expect(player.removedIDs == ["d", "c", "b"])
    }

    @Test("A repeated song is cleared occurrence by occurrence")
    func clearsRepeatedSong() async throws {
        let player = UpNextPlayerStub(state: try makeState(["a", "b", "a", "b"], current: 0))
        #expect(await UpNextClearing.clear(player: player, state: player.state) == 3)
        #expect(player.state.queue.map(\.id) == ["a"])
    }

    @Test("Nothing after the last song, or a radio stream, leaves the queue alone")
    func nothingToClear() async throws {
        let state = try makeState(["a", "b"], current: 1)
        #expect(UpNextClearing.nextRemoval(in: state) == nil)
        let radio = try makeState(["a", "b"], current: 0)
        let station = try JSONSerialization.data(withJSONObject: ["id": "r", "name": "Radio",
                                                                  "streamUrl": "https://radio.example.com"])
        radio.currentRadio = try JSONDecoder().decode(InternetRadioStation.self, from: station)
        #expect(UpNextClearing.nextRemoval(in: radio) == nil)
    }

    @Test("A refused removal stops clearing instead of looping")
    func stopsWhenPlayerRefuses() async throws {
        let player = UpNextPlayerStub(state: try makeState(["a", "b", "c"], current: 0))
        player.refusesRemoval = true
        #expect(await UpNextClearing.clear(player: player, state: player.state) == 0)
        #expect(player.state.queue.count == 3)
    }

    private func makeState(_ ids: [String], current: Int) throws -> PlayerState {
        let state = PlayerState()
        state.queue = try ids.map { id in
            let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": id, "isDir": false])
            return DisplayableSong(from: try JSONDecoder().decode(Song.self, from: data))
        }
        state.currentIndex = current
        state.currentTrack = state.queue[current]
        state.position = 42
        state.playbackState = .playing
        return state
    }
}

/// Removes through QueueEditing, as PlayerService does, and records the order of removals.
@MainActor
private final class UpNextPlayerStub: PlayerServiceProtocol {
    let state: PlayerState
    var refusesRemoval = false
    private(set) var removedIDs: [String] = []

    init(state: PlayerState) { self.state = state }

    func removeQueueTrack(_ selection: QueueTrackSelection) async -> QueueRemoval? {
        guard !refusesRemoval, let removal = QueueEditing.remove(selection, from: state) else { return nil }
        removedIDs.append(removal.song.id)
        return removal
    }

    func play(tracks: [DisplayableSong], startIndex: Int) async throws {}
    func resume() async {}
    func pause() async {}
    func stop() async {}
    func skipToNext() async throws {}
    func skipToPrevious() async throws {}
    func selectQueueTrack(_ selection: QueueTrackSelection) async throws -> Bool { true }
    func seek(to position: TimeInterval) async {}
    func setRepeatMode(_ mode: RepeatMode) async {}
    func toggleShuffle() async {}
    func appendToQueue(_ tracks: [DisplayableSong]) async {}
    func playNext(_ song: DisplayableSong) async {}
    func playNext(_ songs: [DisplayableSong]) async {}
    func addToQueue(_ song: DisplayableSong) async {}
    func addToQueue(_ songs: [DisplayableSong]) async {}
    func removeFromQueue(at index: Int) async {}
    func restoreQueueTrack(_ removal: QueueRemoval) async -> Bool { false }
    func moveQueueTrack(_ selection: QueueTrackSelection, toIndex: Int) async {}
    func moveInQueue(fromIndex: Int, toIndex: Int) async {}
    func restoreSession() async {}
    func handleNetworkPathChanged(_ event: NetworkPathEvent) async {}
    func playRadio(_ station: InternetRadioStation) async throws {}
    func playSmartShuffle() async throws {}
    func playInstantMix(from seed: InstantMixSeed, startingWith seedTrack: DisplayableSong?) async throws {}
    func setAutoExtendEnabled(_ enabled: Bool) async {}
    func setVolume(_ volume: Float) async {}
    func applySleepFade(_ level: Float) async {}
    func togglePlayPause() async {}
    func saveCurrentPosition() async {}
    func replayGainSettingsDidChange() async {}
    func crossfadeSettingsDidChange() async {}
    nonisolated func stopAudioEngineSync() {}
}
