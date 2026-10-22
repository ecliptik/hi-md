import Foundation
import Testing
@testable import Minidisc

@Suite("PlayerService.nowPlayingNeedsPositionPush")
struct NowPlayingPositionPushTests {
    private let anchor = NowPlayingPositionAnchor(elapsed: 10, duration: 200, uptime: 1_000)

    @Test func pushesFirstTickOfATrack() {
        #expect(PlayerService.nowPlayingNeedsPositionPush(anchor: nil, elapsed: 0, duration: 200, uptime: 1_000))
    }

    @Test func skipsWhilePlaybackMatchesTheSystemExtrapolation() {
        for second in 1...60 {
            let uptime = 1_000 + TimeInterval(second)
            #expect(!PlayerService.nowPlayingNeedsPositionPush(
                anchor: anchor, elapsed: 10 + TimeInterval(second) - 0.3, duration: 200, uptime: uptime
            ))
        }
    }

    @Test func pushesAfterAStallOrAJump() {
        // Buffering froze the clock for 3 s while the system kept advancing it.
        #expect(PlayerService.nowPlayingNeedsPositionPush(anchor: anchor, elapsed: 10, duration: 200, uptime: 1_003))
        #expect(PlayerService.nowPlayingNeedsPositionPush(anchor: anchor, elapsed: 40, duration: 200, uptime: 1_010))
    }

    @Test func pushesWhenTheDurationIsRefined() {
        #expect(PlayerService.nowPlayingNeedsPositionPush(anchor: anchor, elapsed: 11, duration: 245, uptime: 1_001))
        #expect(!PlayerService.nowPlayingNeedsPositionPush(anchor: anchor, elapsed: 11, duration: 200.4, uptime: 1_001))
    }
}

@Suite("PlayerService.progressTickInterval")
struct ProgressTickIntervalTests {
    @Test func visibleAppKeepsTheProgressBarSmooth() {
        let interval = PlayerService.progressTickInterval(isAppVisible: true)
        #expect(interval.period == .milliseconds(500))
        #expect(interval.tolerance <= .milliseconds(100))
    }

    @Test func hiddenAppTicksLessOftenButFarInsideThePreloadWindow() {
        let interval = PlayerService.progressTickInterval(isAppVisible: false)
        #expect(interval.period == .seconds(1))
        // The standby preload is scheduled 15 s before the transition; a late tick must not miss it.
        #expect(interval.period + interval.tolerance < .seconds(15))
        // A late tick must still count as continuous listening time.
        var tracker = PlaybackProgressTracker()
        tracker.startTrack()
        tracker.record(progress: 10, isPlaying: true)
        tracker.record(progress: 10 + 1.5 + 0.4, isPlaying: true)
        #expect(abs(tracker.accumulatedTime - 1.9) < 0.0001)
    }
}

@Suite("CacheSettings.cacheWhilePlaying")
@MainActor
struct CacheWhilePlayingSettingTests {
    @Test func enabledByDefaultAndPreferenceSurvivesRelaunch() throws {
        let name = "CacheWhilePlayingSettingTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = CacheSettings(defaults: defaults)
        #expect(settings.cacheWhilePlaying)
        settings.cacheWhilePlaying = false
        #expect(!CacheSettings(defaults: defaults).cacheWhilePlaying)
    }
}
