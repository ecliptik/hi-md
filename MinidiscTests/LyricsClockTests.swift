import Foundation
import SwiftData
import SwiftSonic
import Testing
@testable import Minidisc

/// The lyrics' clock: the scrubber while it's dragged, then the seek's target until the player
/// gets there, then the player.
@Suite("Lyrics clock")
struct LyricsClockTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func followsThePlayerWhenNothingIsScrubbedOrSought() {
        let clock = LyricsClock()
        #expect(clock.isIdle)
        #expect(clock.time(playbackPosition: 42, at: start) == 42)
    }

    @Test func aDragLeadsBeforeAnySeek() {
        var clock = LyricsClock()
        clock.scrub(to: 90)
        #expect(clock.isScrubbing)
        #expect(clock.time(playbackPosition: 10, at: start) == 90)
        clock.scrub(to: 95)
        #expect(clock.time(playbackPosition: 10, at: start) == 95)
        // Cancelled, the player's position is back.
        clock.cancelScrub()
        #expect(clock.time(playbackPosition: 10, at: start) == 10)
    }

    @Test func aSeekHoldsItsTargetUntilThePlayerGetsThere() {
        var clock = LyricsClock()
        clock.scrub(to: 90)
        clock.seek(to: 90, at: start)
        #expect(!clock.isScrubbing)
        // The player still reports where it was: no flash back to the old line.
        #expect(clock.time(playbackPosition: 10, at: start.addingTimeInterval(0.4)) == 90)
        clock.settle(playbackPosition: 10.25, at: start.addingTimeInterval(0.4))
        #expect(clock.pendingSeek != nil)
        // Within half a second of the target, the player's own position takes over.
        clock.settle(playbackPosition: 89.7, at: start.addingTimeInterval(0.6))
        #expect(clock.pendingSeek == nil)
        #expect(clock.time(playbackPosition: 91, at: start.addingTimeInterval(1.6)) == 91)
    }

    @Test func aSeekThatNeverLandsGivesUpAfterATimeout() {
        var clock = LyricsClock()
        clock.seek(to: 120, at: start)
        #expect(clock.time(playbackPosition: 30, at: start.addingTimeInterval(1.4)) == 120)
        let late = start.addingTimeInterval(LyricsClock.catchUpTimeout)
        #expect(clock.time(playbackPosition: 30, at: late) == 30)
        clock.settle(playbackPosition: 30, at: late)
        #expect(clock.isIdle)
    }

    @Test func eachScrubAndSeekCountsOnce() {
        var clock = LyricsClock()
        let before = clock.seekRevision
        clock.scrub(to: 10)
        clock.scrub(to: 11)
        #expect(clock.seekRevision == before + 1)
        clock.seek(to: 11, at: start)
        #expect(clock.seekRevision == before + 2)
        // The scrubber and then the player report the same seek: it counts once.
        clock.seek(to: 11.01, at: start.addingTimeInterval(0.05))
        #expect(clock.seekRevision == before + 2)
        clock.seek(to: 40, at: start.addingTimeInterval(0.1))
        #expect(clock.seekRevision == before + 3)
        #expect(clock.pendingSeek?.target == 40)
    }

    @Test func ignoresInvalidPositionsAndResets() {
        var clock = LyricsClock()
        clock.scrub(to: .nan)
        clock.seek(to: .infinity, at: start)
        #expect(clock.isIdle)
        clock.scrub(to: -3)
        #expect(clock.time(playbackPosition: 5, at: start) == 0)
        clock.seek(to: 50, at: start)
        clock.reset()
        #expect(clock.isIdle)
    }

    @Test func aFewLinesGlideAndALongerJumpCuts() {
        #expect(LyricsScrollPolicy.animates(from: 4, to: 5))
        #expect(LyricsScrollPolicy.animates(from: 4, to: 7))
        #expect(LyricsScrollPolicy.animates(from: 7, to: 4))
        #expect(!LyricsScrollPolicy.animates(from: 4, to: 8))
        #expect(!LyricsScrollPolicy.animates(from: 30, to: 2))
        #expect(!LyricsScrollPolicy.animates(from: nil, to: 3))
    }
}

/// The player's state carries the clock: a seek waits for the position, a new song clears it.
@Suite("Player state lyrics time")
@MainActor
struct PlayerStateLyricsTimeTests {
    @Test func positionUpdatesSettleASeek() {
        let state = PlayerState()
        state.position = 10
        state.noteSeek(to: 100)
        #expect(state.lyricsTime == 100)
        state.position = 10.25
        #expect(state.lyricsTime == 100)
        state.position = 100.1
        #expect(state.lyricsClock.isIdle)
        state.position = 101
        #expect(state.lyricsTime == 101)
    }

    @Test func aNewSongClearsAScrubOrSeek() {
        let state = PlayerState()
        state.currentTrack = LyricsScrubbingFixtures.song(id: "a")
        state.noteScrub(to: 60)
        state.currentTrack = LyricsScrubbingFixtures.song(id: "a")
        #expect(state.lyricsClock.isScrubbing)
        state.currentTrack = LyricsScrubbingFixtures.song(id: "b")
        #expect(state.lyricsClock.isIdle)
    }
}

/// Lyrics views follow the scrubber and seeks at once, through the view model.
@Suite("LyricsViewModel — scrubbing and seeking")
@MainActor
struct LyricsScrubbingViewModelTests {
    @Test func aDragMovesTheLineBeforeTheSeek() async throws {
        let (vm, state, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        #expect(vm.currentLineIndex == 0)
        state.noteScrub(to: 5.5)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == 5)
        state.noteScrub(to: 6.2)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == 6)
        #expect(vm.scrollRequest?.index == 6)
        #expect(vm.scrollRequest?.animated == true)
    }

    @Test func letGoTheLineHoldsUntilThePlayerCatchesUp() async throws {
        let (vm, state, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        state.noteScrub(to: 12.3)
        state.noteSeek(to: 12.3)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == 12)
        // A playback tick from before the seek lands doesn't bring the old line back.
        state.position = 0.4
        vm.syncToPlayback()
        #expect(vm.currentLineIndex == 12)
        // The player gets there, and its own position leads again.
        state.position = 12.4
        #expect(state.lyricsClock.isIdle)
        state.position = 13.1
        vm.syncToPlayback()
        #expect(vm.currentLineIndex == 13)
    }

    @Test func aSeekThatNeverLandsFallsBackToThePlayer() async throws {
        let (vm, state, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        state.position = 2.2
        state.noteSeek(to: 15)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == 15)
        vm.now = { Date.now.addingTimeInterval(LyricsClock.catchUpTimeout + 0.1) }
        vm.syncToPlayback()
        #expect(vm.currentLineIndex == 2)
    }

    @Test func aLongJumpCutsStraightToTheLine() async throws {
        let (vm, state, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        state.noteSeek(to: 18.5)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == 18)
        #expect(vm.scrollRequest?.index == 18)
        #expect(vm.scrollRequest?.animated == false)
        // Back a couple of lines: that glides.
        state.noteSeek(to: 16.5)
        vm.lyricsClockChanged()
        #expect(vm.scrollRequest?.index == 16)
        #expect(vm.scrollRequest?.animated == true)
    }

    @Test func aSeekMakesTheLyricsFollowAgain() async throws {
        let (vm, state, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        vm.autoScrollEnabled = false
        vm.userStartedScrolling()
        let opening = vm.scrollRequest
        // Playback alone doesn't scroll lyrics the listener scrolled away from.
        state.position = 3.5
        vm.syncToPlayback()
        #expect(vm.currentLineIndex == 3)
        #expect(vm.scrollRequest == opening)
        // A seek follows again, even to the line already current.
        state.noteSeek(to: 3.6)
        vm.lyricsClockChanged()
        #expect(!vm.isUserScrolling)
        #expect(vm.autoScrollEnabled)
        #expect(vm.scrollRequest?.index == 3)
        #expect(vm.scrollRequest?.animated == false)
    }

    @Test func tappingALineHighlightsItAtOnce() async throws {
        let (vm, state, player) = try await LyricsScrubbingFixtures.loadedViewModel()
        vm.userTapped(lineIndex: 9)
        #expect(state.lyricsClock.pendingSeek?.target == 9)
        vm.lyricsClockChanged()
        #expect(vm.currentLineIndex == 9)
        for _ in 0..<20 where player.seekCalledWith == nil { await Task.yield() }
        #expect(player.seekCalledWith == 9)
    }

    @Test func aShownViewFollowsTheScrubberWithoutAPlaybackTick() async throws {
        let (vm, state, _) = try await LyricsScrubbingFixtures.loadedViewModel()
        vm.setVisible(true)
        defer { vm.setVisible(false) }
        #expect(!vm.isTrackingPlayback)
        state.noteScrub(to: 7.5)
        for _ in 0..<50 where vm.currentLineIndex != 7 { await Task.yield() }
        #expect(vm.currentLineIndex == 7)
        state.noteSeek(to: 11.2)
        for _ in 0..<50 where vm.currentLineIndex != 11 { await Task.yield() }
        #expect(vm.currentLineIndex == 11)
    }
}

@MainActor
enum LyricsScrubbingFixtures {
    static func song(id: String) -> DisplayableSong {
        DisplayableSong(
            id: id, title: "Test song", artist: "Test artist", albumId: "album-1", albumName: "Test album",
            artistId: "artist-1", genre: nil, duration: 180, trackNumber: 1, isDownloaded: false,
            coverArtId: nil, audioFormat: "FLAC", replayGainTrackGain: nil, replayGainTrackPeak: nil,
            replayGainAlbumGain: nil, replayGainAlbumPeak: nil, replayGainBaseGain: nil, replayGainFallbackGain: nil
        )
    }

    /// Twenty synced lines, one a second, loaded and on line 0.
    static func loadedViewModel() async throws -> (LyricsViewModel, PlayerState, MockPlayerService) {
        let serverID = UUID()
        let container = try ModelContainer(for: Schema([CachedLyrics.self]),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let lines = (0..<20).map { Line(value: "Line \($0)", start: $0 * 1000) }
        let list = LyricsList(structuredLyrics: [StructuredLyrics(lang: "en", synced: true, line: lines)])
        let context = ModelContext(container)
        context.insert(CachedLyrics(songId: "song-1", serverId: serverID, jsonPayload: try JSONEncoder().encode(list)))
        try context.save()
        let player = MockPlayerService()
        let state = PlayerState()
        let vm = LyricsViewModel(track: song(id: "song-1"), serverId: serverID, source: .navidrome,
                                 lyricsService: LyricsService(serverService: MockLyricsServerService(), modelContainer: container),
                                 playerService: player, playerState: state)
        await vm.load()
        return (vm, state, player)
    }
}
