import Foundation
import Observation
import OSLog

/// Pauses playback after a set time, or at the end of the current song or album, fading out
/// over the last few seconds.
@Observable
@MainActor
final class SleepTimer {
    enum Mode: Equatable, Hashable {
        case minutes(Int)
        case endOfSong
        case endOfAlbum
    }

    static let durations = [15, 30, 45, 60, 90]
    static let fadeDuration: TimeInterval = 10

    private(set) var mode: Mode?
    /// When a timed sleep ends; nil for end of song or album.
    private(set) var endsAt: Date?

    @ObservationIgnored private let playerState: PlayerState
    @ObservationIgnored private let player: any PlayerServiceProtocol
    @ObservationIgnored private var task: Task<Void, Never>?

    init(playerState: PlayerState, player: any PlayerServiceProtocol) {
        self.playerState = playerState
        self.player = player
    }

    var isActive: Bool { mode != nil }

    func start(_ mode: Mode, now: Date = .now) {
        cancel()
        self.mode = mode
        if case .minutes(let minutes) = mode { endsAt = now.addingTimeInterval(TimeInterval(minutes * 60)) }
        let songID = playerState.currentTrack?.id
        let albumID = playerState.currentTrack?.albumId
        task = Task { [weak self] in await self?.run(mode, songID: songID, albumID: albumID) }
        Logger.player.info("Sleep timer started: \(String(describing: mode), privacy: .public)")
    }

    func cancel() {
        task?.cancel()
        task = nil
        if mode != nil { Task { [player] in await player.applySleepFade(1) } }
        mode = nil
        endsAt = nil
    }

    private func run(_ mode: Mode, songID: String?, albumID: String?) async {
        while !Task.isCancelled {
            let remaining = remainingSeconds(mode, songID: songID, albumID: albumID)
            if remaining <= 0 {
                await finish()
                return
            }
            if remaining <= Self.fadeDuration {
                await player.applySleepFade(Float(remaining / Self.fadeDuration))
            }
            do { try await Task.sleep(for: .milliseconds(remaining <= Self.fadeDuration ? 250 : 1000)) } catch { return }
        }
    }

    /// Seconds until playback should stop; 0 or less once it should.
    func remainingSeconds(_ mode: Mode, songID: String?, albumID: String?, now: Date = .now) -> TimeInterval {
        let track = playerState.currentTrack
        let left = max(0, playerState.duration - playerState.position)
        switch mode {
        case .minutes:
            return endsAt.map { $0.timeIntervalSince(now) } ?? 0
        case .endOfSong:
            // The next song has started, or nothing is playing.
            guard let track, track.id == songID else { return 0 }
            return playerState.duration > 0 ? left : .infinity
        case .endOfAlbum:
            guard let track, track.albumId == albumID else { return 0 }
            let nextIndex = playerState.currentIndex + 1
            let nextIsSameAlbum = playerState.queue.indices.contains(nextIndex)
                && playerState.queue[nextIndex].albumId == albumID
            return nextIsSameAlbum || playerState.duration <= 0 ? .infinity : left
        }
    }

    private func finish() async {
        await player.pause()
        await player.applySleepFade(1)
        mode = nil
        endsAt = nil
        task = nil
        Logger.player.info("Sleep timer paused playback")
    }
}
