import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Sleep timer")
@MainActor
struct SleepTimerTests {
    private func song(_ id: String, album: String) -> DisplayableSong {
        DisplayableSong(from: Song(id: id, title: id, duration: 200, albumId: album))
    }

    private func state(queue: [DisplayableSong], index: Int, position: TimeInterval) -> PlayerState {
        let state = PlayerState()
        state.queue = queue
        state.currentIndex = index
        state.currentTrack = queue[index]
        state.duration = 200
        state.position = position
        return state
    }

    @Test func timedSleepCountsDownToItsEnd() {
        let now = Date()
        let timer = SleepTimer(playerState: PlayerState(), player: MockPlayerService())
        timer.start(.minutes(15), now: now)
        defer { timer.cancel() }
        #expect(timer.remainingSeconds(.minutes(15), songID: nil, albumID: nil, now: now) == 15 * 60)
        #expect(timer.remainingSeconds(.minutes(15), songID: nil, albumID: nil, now: now.addingTimeInterval(15 * 60 + 1)) < 0)
    }

    @Test func endOfSongStopsWhenTheSongEndsOrChanges() {
        let queue = [song("a", album: "x"), song("b", album: "x")]
        let state = state(queue: queue, index: 0, position: 150)
        let timer = SleepTimer(playerState: state, player: MockPlayerService())
        #expect(timer.remainingSeconds(.endOfSong, songID: "a", albumID: "x") == 50)
        state.currentTrack = queue[1]
        #expect(timer.remainingSeconds(.endOfSong, songID: "a", albumID: "x") == 0)
    }

    @Test func endOfAlbumWaitsForTheAlbumsLastSong() {
        let queue = [song("a", album: "x"), song("b", album: "x"), song("c", album: "y")]
        let state = state(queue: queue, index: 0, position: 150)
        let timer = SleepTimer(playerState: state, player: MockPlayerService())
        #expect(timer.remainingSeconds(.endOfAlbum, songID: "a", albumID: "x") == .infinity)
        state.currentIndex = 1
        state.currentTrack = queue[1]
        #expect(timer.remainingSeconds(.endOfAlbum, songID: "a", albumID: "x") == 50)
        state.currentIndex = 2
        state.currentTrack = queue[2]
        #expect(timer.remainingSeconds(.endOfAlbum, songID: "a", albumID: "x") == 0)
    }

    @Test func cancellingClearsTheMode() {
        let timer = SleepTimer(playerState: PlayerState(), player: MockPlayerService())
        timer.start(.endOfSong)
        #expect(timer.isActive)
        timer.cancel()
        #expect(!timer.isActive)
        #expect(timer.endsAt == nil)
    }
}
