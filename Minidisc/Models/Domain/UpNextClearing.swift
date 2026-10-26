import Foundation

/// Clears the songs after the current one, for the Mac app's queue Clear button.
///
/// The player has no bulk clear, so this removes one song at a time through its ordinary removal,
/// which keeps the current song playing and re-prepares the gapless or crossfade transition only if
/// the next song changes. Removing from the end changes the next song just once, at the last step.
@MainActor
enum UpNextClearing {
    /// The last song after the current one, as a removal request; nil when nothing follows.
    static func nextRemoval(in state: PlayerState) -> QueueTrackSelection? {
        guard !state.isLiveStream, let last = state.queue.indices.last, last > state.currentIndex else { return nil }
        return QueueTrackSelection(playerState: state, destinationIndex: last, destinationTrackID: state.queue[last].id)
    }

    /// Returns how many songs were removed. Stops early if the player refuses a removal, for
    /// example because a new queue started meanwhile.
    @discardableResult
    static func clear(player: any PlayerServiceProtocol, state: PlayerState) async -> Int {
        var removed = 0
        let limit = state.queue.count
        while removed < limit, let selection = nextRemoval(in: state) {
            guard await player.removeQueueTrack(selection) != nil else { break }
            removed += 1
        }
        return removed
    }
}
