import AVFoundation
import Foundation
import Testing
@testable import Minidisc

// MARK: - shouldSchedulePrefetch

@Suite("PlayerService.shouldSchedulePrefetch")
struct ShouldSchedulePrefetchTests {

    @Test func gaplessPreloadStillRunsWhenCrossfadeIsOff() {
        // "Off" disables overlap, not the warm standby deck required for a butt-splice.
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 0) == true)
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 5) == true)
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 15) == true)
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 0, remaining: 100) == false)
    }

    @Test func firesWhenRemainingWithinThreshold() {
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 8, remaining: 20) == true)
    }

    @Test func exactlyAtThreshold() {
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 5, remaining: 20) == true)
    }

    @Test func doesNotFireBeyondThreshold() {
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 5, remaining: 21) == false)
    }

    @Test func firesNearEndOfTrack() {
        #expect(PlayerService.shouldSchedulePrefetch(crossfadeDuration: 3, remaining: 2) == true)
    }
}

@Suite("PlayerService.shouldProtectTransitionFromCaching")
struct ShouldProtectTransitionFromCachingTests {
    @Test func cancelsCacheBeforeStandbyPreloadWindow() {
        #expect(PlayerService.shouldProtectTransitionFromCaching(crossfadeDuration: 5, remaining: 35))
        #expect(!PlayerService.shouldProtectTransitionFromCaching(crossfadeDuration: 5, remaining: 35.1))
    }

    @Test func protectsGaplessTransitionWhenCrossfadeIsOff() {
        #expect(PlayerService.shouldProtectTransitionFromCaching(crossfadeDuration: 0, remaining: 30))
        #expect(!PlayerService.shouldProtectTransitionFromCaching(crossfadeDuration: 0, remaining: 30.1))
    }
}

@Suite("AVPlayerEngine ReplayGain routing")
struct AVPlayerEngineReplayGainRoutingTests {
    @Test func attenuationUsesDeckVolumeWithoutAudioTap() {
        #expect(!AVPlayerEngine.requiresReplayGainTap(linearGain: 0.5))
        #expect(AVPlayerEngine.replayGainDeckVolumeScale(linearGain: 0.5, tapInstalled: false) == 0.5)
    }

    @Test func boostRequiresAudioTap() {
        #expect(AVPlayerEngine.requiresReplayGainTap(linearGain: 1.5))
        #expect(AVPlayerEngine.replayGainDeckVolumeScale(linearGain: 1.5, tapInstalled: false) == 1)
    }

    @Test func installedTapOwnsTheEntireGain() {
        #expect(AVPlayerEngine.replayGainDeckVolumeScale(linearGain: 0.5, tapInstalled: true) == 1)
    }

    @Test func equalizerRequiresAudioTapEvenWithoutBoost() {
        #expect(!AVPlayerEngine.requiresAudioTap(linearGain: 0.5, equalizerEnabled: false))
        #expect(AVPlayerEngine.requiresAudioTap(linearGain: 0.5, equalizerEnabled: true))
        #expect(AVPlayerEngine.requiresAudioTap(linearGain: 1.5, equalizerEnabled: false))
    }
}

@Suite("AVPlayerEngine forward buffer", .serialized)
struct AVPlayerEngineForwardBufferTests {
    /// Hands the engine its two decks and keeps them, so the items it loads can be inspected.
    private nonisolated final class DeckRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var players: [AVPlayer] = []
        var decks: [AVPlayer] { lock.withLock { players } }
        func make() -> AVPlayer {
            let player = AVPlayer()
            lock.withLock { players.append(player) }
            return player
        }
    }

    private let remote = URL(string: "https://playback.invalid/rest/stream?id=a")!
    private let nextRemote = URL(string: "https://playback.invalid/rest/stream?id=b")!

    @Test func remoteItemsAskForAFewMinutesOfAudioOnBothDecks() {
        let recorder = DeckRecorder()
        let engine = AVPlayerEngine(playerFactory: { recorder.make() })
        defer { engine.stop() }
        engine.play(trackID: "a", url: remote, headers: [:])
        engine.preloadNext(trackID: "b", url: nextRemote, headers: [:], crossfadeDuration: 6, leadInTrim: 0, replayGainDB: 0, expectedCurrentTrackID: "a")
        let items = recorder.decks.compactMap(\.currentItem)
        #expect(items.count == 2)
        #expect(AVPlayerEngine.remoteForwardBufferDuration >= 180 && AVPlayerEngine.remoteForwardBufferDuration <= 300)
        #expect(items.allSatisfy { $0.preferredForwardBufferDuration == AVPlayerEngine.remoteForwardBufferDuration })
    }

    @Test func localFilesKeepTheSystemDefault() {
        let recorder = DeckRecorder()
        let engine = AVPlayerEngine(playerFactory: { recorder.make() })
        defer { engine.stop() }
        let file = URL(fileURLWithPath: "/tmp/forward-buffer-fixture.m4a")
        engine.play(trackID: "a", url: file, headers: [:])
        engine.preloadNext(trackID: "b", url: nextRemote, headers: [:], crossfadeDuration: 0, leadInTrim: 0, replayGainDB: 0, expectedCurrentTrackID: "a")
        let decks = recorder.decks
        #expect(decks.first?.currentItem?.preferredForwardBufferDuration == 0)
        #expect(decks.last?.currentItem?.preferredForwardBufferDuration == AVPlayerEngine.remoteForwardBufferDuration)
        #expect(AVPlayerEngine.preferredForwardBufferDuration(for: file) == 0)
    }

    @Test func convertedStreamsBufferTheWholeSongOnBothDecks() {
        let recorder = DeckRecorder()
        let engine = AVPlayerEngine(playerFactory: { recorder.make() })
        defer { engine.stop() }
        let transcoded = URL(string: "https://playback.invalid/rest/stream?id=a&format=opus&estimateContentLength=true")!
        let nextTranscoded = URL(string: "https://playback.invalid/rest/stream?id=b&estimateContentLength=true")!
        engine.play(trackID: "a", url: transcoded, headers: [:])
        engine.preloadNext(trackID: "b", url: nextTranscoded, headers: [:], crossfadeDuration: 0, leadInTrim: 0, replayGainDB: 0, expectedCurrentTrackID: "a")
        let items = recorder.decks.compactMap(\.currentItem)
        #expect(items.count == 2)
        #expect(AVPlayerEngine.transcodedForwardBufferDuration >= 600)
        #expect(items.allSatisfy { $0.preferredForwardBufferDuration == AVPlayerEngine.transcodedForwardBufferDuration })
        // An exact length (no estimate) keeps the ordinary remote buffer.
        let exact = URL(string: "https://playback.invalid/rest/stream?id=a&estimateContentLength=false")!
        #expect(AVPlayerEngine.preferredForwardBufferDuration(for: exact) == AVPlayerEngine.remoteForwardBufferDuration)
    }
}

@Suite("AVPlayerEngine exact end cap", .serialized)
struct AVPlayerEngineExactEndCapTests {
    private nonisolated final class DeckRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var players: [AVPlayer] = []
        var decks: [AVPlayer] { lock.withLock { players } }
        func make() -> AVPlayer {
            let player = AVPlayer()
            lock.withLock { players.append(player) }
            return player
        }
    }

    private let remote = URL(string: "https://playback.invalid/rest/stream?id=a&estimateContentLength=true")!

    private func endTime(_ recorder: DeckRecorder) -> Double? {
        guard let time = recorder.decks.first?.currentItem?.forwardPlaybackEndTime, time.isNumeric else { return nil }
        return CMTimeGetSeconds(time)
    }

    @Test func capsTheCurrentRemoteItemAndSurvivesAClearedTrim() {
        let recorder = DeckRecorder()
        let engine = AVPlayerEngine(playerFactory: { recorder.make() })
        defer { engine.stop() }
        engine.play(trackID: "a", url: remote, headers: [:])
        engine.capPlayback(atExactDuration: 247.5, expectedCurrentTrackID: "a")
        #expect(endTime(recorder) == 247.5)
        // Restoring the full length (trim 0) restores the cap, not an open end.
        engine.setTrackEndTrim(0, expectedCurrentTrackID: "a")
        #expect(endTime(recorder) == 247.5)
    }

    @Test func anEarlierEndStillWins() {
        let recorder = DeckRecorder()
        let engine = AVPlayerEngine(playerFactory: { recorder.make() })
        defer { engine.stop() }
        engine.play(trackID: "a", url: remote, headers: [:])
        recorder.decks.first?.currentItem?.forwardPlaybackEndTime = CMTime(seconds: 240, preferredTimescale: 600)
        engine.capPlayback(atExactDuration: 247.5, expectedCurrentTrackID: "a")
        #expect(endTime(recorder) == 240)
    }

    @Test func leavesLocalFilesAndOtherSongsAlone() {
        let recorder = DeckRecorder()
        let engine = AVPlayerEngine(playerFactory: { recorder.make() })
        defer { engine.stop() }
        engine.play(trackID: "a", url: remote, headers: [:])
        engine.capPlayback(atExactDuration: 247.5, expectedCurrentTrackID: "b")
        #expect(endTime(recorder) == nil)
        engine.play(trackID: "c", url: URL(fileURLWithPath: "/tmp/end-cap-fixture.m4a"), headers: [:])
        engine.capPlayback(atExactDuration: 100, expectedCurrentTrackID: "c")
        #expect(recorder.decks.compactMap(\.currentItem).allSatisfy { !$0.forwardPlaybackEndTime.isNumeric })
    }
}

@Suite("AVPlayerEngine equal-power crossfade")
struct AVPlayerEngineEqualPowerCrossfadeTests {
    @Test func endpointsRouteOneDeckAtATime() {
        let start = AVPlayerEngine.equalPowerLevels(progress: 0)
        let end = AVPlayerEngine.equalPowerLevels(progress: 1)

        #expect(abs(start.outgoing - 1) < 0.0001)
        #expect(abs(start.incoming) < 0.0001)
        #expect(abs(end.outgoing) < 0.0001)
        #expect(abs(end.incoming - 1) < 0.0001)
    }

    @Test func midpointPreservesCombinedPower() {
        let midpoint = AVPlayerEngine.equalPowerLevels(progress: 0.5)
        let combinedPower = midpoint.outgoing * midpoint.outgoing
            + midpoint.incoming * midpoint.incoming

        #expect(abs(combinedPower - 1) < 0.0001)
        #expect(abs(midpoint.outgoing - midpoint.incoming) < 0.0001)
    }

    @Test func progressIsClampedToTheRamp() {
        #expect(AVPlayerEngine.equalPowerLevels(progress: -1).outgoing == 1)
        #expect(abs(AVPlayerEngine.equalPowerLevels(progress: 2).outgoing) < 0.0001)
    }
}

@Suite("PlayerService.effectiveCrossfadeOverlap")
struct EffectiveCrossfadeOverlapTests {
    @Test func usesConfiguredDurationForOrdinaryTransitions() {
        #expect(PlayerService.effectiveCrossfadeOverlap(
            duration: 5,
            disableForGapless: true,
            isGaplessPair: false
        ) == 5)
    }

    @Test func preservesConsecutiveAlbumTracksWhenRequested() {
        #expect(PlayerService.effectiveCrossfadeOverlap(
            duration: 5,
            disableForGapless: true,
            isGaplessPair: true
        ) == 0)
    }

    @Test func canCrossfadeConsecutiveAlbumTracks() {
        #expect(PlayerService.effectiveCrossfadeOverlap(
            duration: 5,
            disableForGapless: false,
            isGaplessPair: true
        ) == 5)
    }
}

// MARK: - isAlbumSequencePair

@Suite("PlayerService.isAlbumSequencePair")
struct IsAlbumSequencePairTests {

    @Test func sameAlbumConsecutiveIsGapless() {
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1,
            currentTrackNumber: 3,
            nextAlbumId: "A", nextDiscNumber: 1, nextTrackNumber: 4
        ) == true)
    }

    @Test func differentAlbumIsNotGapless() {
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1,
            currentTrackNumber: 3,
            nextAlbumId: "B", nextDiscNumber: 1, nextTrackNumber: 4
        ) == false)
    }

    @Test func nonConsecutiveIsNotGapless() {
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1,
            currentTrackNumber: 3,
            nextAlbumId: "A", nextDiscNumber: 1, nextTrackNumber: 5
        ) == false)
    }

    @Test func nextDiscStartsAContinuousAlbumSequence() {
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1, currentTrackNumber: 12,
            nextAlbumId: "A", nextDiscNumber: 2, nextTrackNumber: 1
        ))
    }

    @Test func skippedDiscIsNotContinuous() {
        #expect(!PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1, currentTrackNumber: 12,
            nextAlbumId: "A", nextDiscNumber: 3, nextTrackNumber: 1
        ))
    }

    @Test func nilAlbumIdIsNotGapless() {
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: nil, currentDiscNumber: 1,
            currentTrackNumber: 3,
            nextAlbumId: "A", nextDiscNumber: 1, nextTrackNumber: 4
        ) == false)
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1,
            currentTrackNumber: 3,
            nextAlbumId: nil, nextDiscNumber: 1, nextTrackNumber: 4
        ) == false)
    }

    @Test func nilTrackNumberIsNotGapless() {
        #expect(PlayerService.isAlbumSequencePair(
            currentAlbumId: "A", currentDiscNumber: 1,
            currentTrackNumber: nil,
            nextAlbumId: "A", nextDiscNumber: 1, nextTrackNumber: 4
        ) == false)
    }
}

@Suite("PlayerService.clampedSeekTarget")
struct ClampedSeekTargetTests {
    @Test func clampsMalformedAndOutOfRangeTargets() {
        #expect(PlayerService.clampedSeekTarget(requested: .nan, stateDuration: 180, engineDuration: 180) == nil)
        #expect(PlayerService.clampedSeekTarget(requested: -20, stateDuration: 180, engineDuration: 180) == 0)
        #expect(PlayerService.clampedSeekTarget(requested: 250, stateDuration: 180, engineDuration: 200) == 200)
    }

    @Test func usesUnboundedNonnegativeTargetWhenDurationIsUnknown() {
        #expect(PlayerService.clampedSeekTarget(requested: 42, stateDuration: 0, engineDuration: 0) == 42)
    }
}
