/// A snapshot of an intentional jump within the current playback queue.
///
/// The captured identities prevent a delayed UI action from selecting the wrong item after the queue
/// changes. Indexes remain part of the request because the same song may legitimately appear more than once.
nonisolated struct QueueTrackSelection: Equatable, Sendable {
    let queueGeneration: UInt64
    let queueRevision: UInt64
    let currentIndex: Int
    let currentTrackID: String
    let destinationIndex: Int
    let destinationTrackID: String

    @MainActor
    init?(playerState: PlayerState, destinationIndex: Int, destinationTrackID: String) {
        let queue = playerState.queue
        let currentIndex = playerState.currentIndex
        guard queue.indices.contains(currentIndex),
              queue.indices.contains(destinationIndex),
              currentIndex != destinationIndex,
              let currentTrack = playerState.currentTrack,
              queue[currentIndex].id == currentTrack.id,
              queue[destinationIndex].id == destinationTrackID else {
            return nil
        }

        self.queueGeneration = playerState.queueGeneration
        self.queueRevision = playerState.queueRevision
        self.currentIndex = currentIndex
        self.currentTrackID = currentTrack.id
        self.destinationIndex = destinationIndex
        self.destinationTrackID = destinationTrackID
    }

    /// Whether the current position is one a selection can start from. Every upcoming row shares it,
    /// so the queue list checks it once instead of building a selection per row.
    @MainActor
    static func canSelect(from playerState: PlayerState) -> Bool {
        let queue = playerState.queue
        guard queue.indices.contains(playerState.currentIndex),
              let currentTrack = playerState.currentTrack else { return false }
        return queue[playerState.currentIndex].id == currentTrack.id
    }

    @MainActor
    func resolve(in playerState: PlayerState) -> Int? {
        let queue = playerState.queue
        guard playerState.queueGeneration == queueGeneration,
              playerState.queueRevision == queueRevision,
              playerState.currentIndex == currentIndex,
              playerState.currentTrack?.id == currentTrackID,
              queue.indices.contains(currentIndex),
              queue[currentIndex].id == currentTrackID,
              queue.indices.contains(destinationIndex),
              queue[destinationIndex].id == destinationTrackID else {
            return nil
        }
        return destinationIndex
    }
}

/// One upcoming song in the queue list. Rows carry only their position and song; the selection is
/// captured when a row is tapped, removed or dragged, so a track change doesn't rebuild a selection
/// for every upcoming song.
nonisolated struct QueueUpcomingRow: Identifiable, Sendable {
    /// Stable across track changes, and distinct for each occurrence of a song.
    struct ID: Hashable, Sendable {
        let generation: UInt64
        let songID: String
        let occurrence: Int
    }

    let id: ID
    let index: Int
    let song: DisplayableSong
    /// The queue revision the row was built from. A row from before an edit can't act on the edited queue.
    let queueRevision: UInt64

    /// How many times each position's song has already appeared earlier in the queue.
    static func occurrences(in queue: [DisplayableSong]) -> [Int] {
        var seen: [String: Int] = [:]
        seen.reserveCapacity(queue.count)
        return queue.map { song in
            let occurrence = seen[song.id, default: 0]
            seen[song.id] = occurrence + 1
            return occurrence
        }
    }

    /// The songs after the current one, at most `limit` of them, or none when the current position
    /// can't start a selection.
    @MainActor
    static func upcoming(in playerState: PlayerState, occurrences: [Int], limit: Int) -> [QueueUpcomingRow] {
        let queue = playerState.queue
        guard QueueTrackSelection.canSelect(from: playerState), occurrences.count == queue.count else { return [] }
        let start = playerState.currentIndex + 1
        let end = start + min(limit, queue.count - start)
        return (start..<end).map { index in
            QueueUpcomingRow(
                id: ID(generation: playerState.queueGeneration, songID: queue[index].id, occurrence: occurrences[index]),
                index: index, song: queue[index], queueRevision: playerState.queueRevision
            )
        }
    }

    /// The selection for this row against the queue as it is now, or nil if the queue has changed
    /// since the row was shown or the row is no longer upcoming.
    @MainActor
    func selection(in playerState: PlayerState) -> QueueTrackSelection? {
        guard playerState.queueGeneration == id.generation,
              playerState.queueRevision == queueRevision,
              index > playerState.currentIndex else { return nil }
        return QueueTrackSelection(playerState: playerState, destinationIndex: index, destinationTrackID: song.id)
    }
}
