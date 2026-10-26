import Foundation

/// Which playback commands apply right now. The Mac app's Controls menu, player bar and menu bar
/// player enable their items from it, so they always agree.
nonisolated struct PlaybackCommandState: Equatable, Sendable {
    var hasTrack: Bool
    var queueCount: Int
    var isLiveStream: Bool
    /// The current song has an album on the server to reveal.
    var hasAlbum: Bool
    /// The current song is a file on this computer rather than a server song.
    var isLocalFile: Bool

    var canTogglePlayback: Bool { hasTrack || isLiveStream }
    var canSkip: Bool { !isLiveStream && queueCount > 0 }
    var canShuffle: Bool { !isLiveStream && queueCount > 1 }
    var canRepeat: Bool { !isLiveStream && hasTrack }
    var canGoToCurrentSong: Bool { hasTrack && hasAlbum && !isLiveStream && !isLocalFile }
    /// Lyrics come from the server or LRCLIB, so a local file or a radio stream has none to show.
    var canShowLyrics: Bool { hasTrack && !isLiveStream && !isLocalFile }
}

extension PlaybackCommandState {
    @MainActor
    init(playerState: PlayerState) {
        let track = playerState.currentTrack
        self.init(
            hasTrack: track != nil,
            queueCount: playerState.queue.count,
            isLiveStream: playerState.isLiveStream,
            hasAlbum: track?.albumId != nil,
            isLocalFile: track?.isLocalFile == true
        )
    }
}

/// Volume steps for the Controls menu's Volume Up and Volume Down.
nonisolated enum PlaybackVolume {
    static let stepsPerFullVolume: Float = 10

    /// The volume after `steps` presses (negative steps lower it), kept within 0...1 and rounded
    /// to a step so repeated presses land on even values.
    static func adjusted(_ volume: Float, steps: Int) -> Float {
        let raw = volume * stepsPerFullVolume + Float(steps)
        return min(1, max(0, raw.rounded() / stepsPerFullVolume))
    }
}
