import Foundation

/// Where the lyrics are in the song: the scrubber's position while the listener drags it, then
/// the seek's target until the player gets there, then the player's own position. Lyrics follow
/// a scrub or a seek at once instead of on the next playback tick, and don't flash back to the
/// old line while the seek completes.
nonisolated struct LyricsClock: Equatable, Sendable {
    /// A seek counts as reached once the player reports a position this close to its target.
    static let catchUpTolerance: TimeInterval = 0.5
    /// After this long the player's position wins again, even if it never reached the target
    /// (a seek that failed or landed elsewhere).
    static let catchUpTimeout: TimeInterval = 1.5

    struct PendingSeek: Equatable, Sendable {
        let target: TimeInterval
        let requestedAt: Date
    }

    /// The scrubber's position while the listener drags it.
    private(set) var scrubPosition: TimeInterval?
    /// A seek the player hasn't reached yet.
    private(set) var pendingSeek: PendingSeek?
    /// Bumped when a scrub starts and on every seek, so the lyrics jump to the line and follow
    /// the song again even after the listener scrolled them.
    private(set) var seekRevision = 0

    var isScrubbing: Bool { scrubPosition != nil }
    /// No scrub or seek in progress: the lyrics follow the player.
    var isIdle: Bool { scrubPosition == nil && pendingSeek == nil }

    /// The listener is dragging a scrubber to `position`.
    mutating func scrub(to position: TimeInterval) {
        guard position.isFinite else { return }
        if scrubPosition == nil { seekRevision &+= 1 }
        scrubPosition = max(position, 0)
    }

    /// The drag ended without a seek.
    mutating func cancelScrub() {
        scrubPosition = nil
    }

    /// A seek to `target` was asked for (a scrubber let go, a tapped lyric line, the lock screen,
    /// Previous restarting the song). The same seek reported again, by the scrubber and then the
    /// player, counts once.
    mutating func seek(to target: TimeInterval, at now: Date) {
        guard target.isFinite else { return }
        let target = max(target, 0)
        scrubPosition = nil
        if let pendingSeek, abs(pendingSeek.target - target) < 0.05,
           now.timeIntervalSince(pendingSeek.requestedAt) < Self.catchUpTimeout {
            return
        }
        pendingSeek = PendingSeek(target: target, requestedAt: now)
        seekRevision &+= 1
    }

    /// The player reported `position`: a seek it has reached, or one that timed out, is let go.
    mutating func settle(playbackPosition position: TimeInterval, at now: Date) {
        guard let pendingSeek, Self.isSettled(pendingSeek, position: position, now: now) else { return }
        self.pendingSeek = nil
    }

    /// The song position the lyrics show.
    func time(playbackPosition position: TimeInterval, at now: Date) -> TimeInterval {
        if let scrubPosition { return scrubPosition }
        if let pendingSeek, !Self.isSettled(pendingSeek, position: position, now: now) { return pendingSeek.target }
        return position
    }

    /// A new song: nothing carries over.
    mutating func reset() {
        scrubPosition = nil
        pendingSeek = nil
    }

    private static func isSettled(_ seek: PendingSeek, position: TimeInterval, now: Date) -> Bool {
        abs(position - seek.target) <= catchUpTolerance || now.timeIntervalSince(seek.requestedAt) >= catchUpTimeout
    }
}

/// How the lyrics scroll to a new line: a few lines glide, a longer jump (a seek, a scrub across
/// the song) cuts straight there rather than racing through every line in between.
nonisolated enum LyricsScrollPolicy {
    static let maxAnimatedDistance = 3

    static func animates(from previous: Int?, to next: Int) -> Bool {
        guard let previous else { return false }
        return abs(next - previous) <= maxAnimatedDistance
    }
}
