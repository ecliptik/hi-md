import Foundation
import Observation
import SwiftSonic

/// UI playback state, updated by PlayerService on MainActor.
@Observable
@MainActor
final class PlayerState {
    /// Internal identity of the current queue session. Async producers verify it
    /// before committing results so an old session cannot append into a replacement.
    @ObservationIgnored var queueGeneration: UInt64 = 0
    /// Every structural queue edit invalidates row actions captured before that edit, including
    /// edits involving two occurrences of the same song.
    @ObservationIgnored private(set) var queueRevision: UInt64 = 0
    var currentTrack: DisplayableSong? {
        didSet {
            if oldValue?.id != currentTrack?.id, !lyricsClock.isIdle { lyricsClock.reset() }
        }
    }
    var queue: [DisplayableSong] = [] {
        didSet { queueRevision &+= 1 }
    }
    var currentIndex: Int = 0
    var playbackState: PlaybackState = .idle {
        didSet {
            switch playbackState {
            case .loading:
                waitingReason = nil
                waitingReason = .loading
            case .playing:
                if oldValue == .paused { waitingReason = .loading }
            case .idle, .paused, .error: waitingReason = nil
            }
        }
    }
    /// Waiting is presentation state, independent from the listener's Play/Pause intent.
    var waitingReason: PlaybackWaitingReason? {
        didSet {
            guard oldValue != waitingReason else { return }
            updateWaitingMessage()
        }
    }
    private var visibleWaitingReason: PlaybackWaitingReason?
    @ObservationIgnored private var waitingMessageTask: Task<Void, Never>?
    @ObservationIgnored private let waitingMessageDelay: Duration
    var wantsPlayback: Bool { playbackState == .playing || playbackState == .loading }

    var playbackStatusMessage: String? {
        if wantsPlayback, let visibleWaitingReason { return visibleWaitingReason.title }
        if case .error(let error) = playbackState { return UserFacingError.from(error).displayMessage }
        if !isPlaybackAvailable { return String(localized: "Reconnect to resume") }
        return nil
    }
    var position: TimeInterval = 0 {
        didSet {
            guard lyricsClock.pendingSeek != nil else { return }
            lyricsClock.settle(playbackPosition: position, at: .now)
        }
    }
    /// Where the lyrics are: a scrub or seek in progress, else `position`. See `LyricsClock`.
    private(set) var lyricsClock = LyricsClock()
    /// Follow Lyrics: whether lyrics views scroll to the line being sung. One setting for every
    /// lyrics view and every song, since each song gets its own lyrics view model; a scrub or
    /// seek turns it back on.
    var followsLyrics = true
    var duration: TimeInterval = 0
    var repeatMode: RepeatMode = .off
    var isShuffled: Bool = false
    /// False when a restored track cannot be resolved (offline + streamed only).
    /// Resets to true when normal playback starts.
    var isPlaybackAvailable: Bool = true
    /// Non-nil when the player is in live stream mode (radio playback).
    /// Mutually exclusive with active queue playback: starting play(tracks:) clears this to nil.
    var currentRadio: InternetRadioStation?
    var isLiveStream: Bool { currentRadio != nil }
    /// Where the current queue came from ("Playing from …"); nil for an ad-hoc queue.
    /// Kept while the queue is that source's queue: skips, appends, Instant Mix fill, auto-extend,
    /// reorder and removal leave it alone. A new unrelated queue, radio or stop clears it, and it
    /// is saved and restored with the session.
    var playbackContext: PlaybackContext?
    /// The context to show: live radio names its station, otherwise the queue's context.
    var displayedPlaybackContext: PlaybackContext? {
        if let currentRadio { return .internetRadio(name: currentRadio.name) }
        return playbackContext
    }
    /// True when the current playback session was started via Smart Shuffle.
    /// Survives skips and pauses; resets on new explicit play, radio or stop. Derived from
    /// `playbackContext`, so a restored Smart Shuffle session keeps it.
    var isSmartShuffleActive: Bool { playbackContext == .smartShuffle }
    /// User preference: when enabled, the player automatically appends a fresh smart shuffle batch
    /// when ≤15 tracks remain. Suppressed by loop mode and live stream mode. AppContainer loads the
    /// persisted initial value from PlaybackPreferences.
    var isAutoExtendEnabled: Bool
    /// Index separating requested tracks from the auto-extended tail; nil means no extension.
    var originalQueueEndIndex: Int?
    /// Whether the current song is one Autoplay added rather than one the listener queued.
    var isPlayingAutoplayedTrack: Bool {
        originalQueueEndIndex.map { currentIndex >= $0 } ?? false
    }
    /// True while the playing song is still being downloaded in full. Pre-caching later songs
    /// waits for it, so it never competes with the song that is playing.
    var currentSongNeedsNetwork = false
    /// True from shortly before a track transition until the next song starts. Background
    /// downloads pause then, so the standby deck has the connection to itself.
    var isNearTrackTransition = false

    init(isAutoExtendEnabled: Bool = false, waitingMessageDelay: Duration = .milliseconds(700)) {
        self.isAutoExtendEnabled = isAutoExtendEnabled
        self.waitingMessageDelay = waitingMessageDelay
    }

    private func updateWaitingMessage() {
        waitingMessageTask?.cancel()
        waitingMessageTask = nil
        guard let reason = waitingReason, wantsPlayback else {
            visibleWaitingReason = nil
            return
        }
        if visibleWaitingReason != nil {
            visibleWaitingReason = reason
            return
        }
        let delay = waitingMessageDelay
        waitingMessageTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return }
            guard let self, self.wantsPlayback, self.waitingReason == reason else { return }
            self.visibleWaitingReason = reason
            self.waitingMessageTask = nil
        }
    }

    // MARK: - Scrubbing and seeking

    /// The song position the lyrics show now.
    var lyricsTime: TimeInterval { lyricsClock.time(playbackPosition: position, at: .now) }

    /// A scrubber is being dragged to `position`; the lyrics follow before the seek.
    func noteScrub(to position: TimeInterval) {
        lyricsClock.scrub(to: position)
    }

    /// The drag ended without seeking.
    func cancelScrub() {
        lyricsClock.cancelScrub()
    }

    /// A seek to `target` was asked for; the lyrics show it until the player gets there.
    func noteSeek(to target: TimeInterval, at now: Date = .now) {
        lyricsClock.seek(to: target, at: now)
    }

    // MARK: - Derived UI state

    var queueIcon: (symbolName: String, isActiveMode: Bool) {
        if repeatMode == .one    { return ("repeat.1", true) }
        if repeatMode == .all    { return ("repeat",   true) }
        if isShuffled            { return ("shuffle",  true) }
        if isSmartShuffleActive  { return ("sparkles", true) }
        return ("list.bullet", false)
    }

    var queueModeBadge: String? {
        if repeatMode == .one   { return "repeat.1" }
        if repeatMode == .all   { return "repeat" }
        if isShuffled           { return "shuffle" }
        if isSmartShuffleActive { return "sparkles" }
        return nil
    }
}
