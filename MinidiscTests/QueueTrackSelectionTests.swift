import Foundation
import Testing
@testable import Minidisc

@Suite("Queue track selection")
@MainActor
struct QueueTrackSelectionTests {
    @Test("resolves while the captured queue is unchanged")
    func resolvesCurrentSnapshot() throws {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two"), makeSong("three")], currentIndex: 1)
        let selection = try #require(
            QueueTrackSelection(playerState: state, destinationIndex: 2, destinationTrackID: "three")
        )

        #expect(selection.resolve(in: state) == 2)
    }

    @Test("rejects invalid or current destinations")
    func rejectsInvalidDestination() {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two")], currentIndex: 0)

        #expect(QueueTrackSelection(playerState: state, destinationIndex: 0, destinationTrackID: "one") == nil)
        #expect(QueueTrackSelection(playerState: state, destinationIndex: 2, destinationTrackID: "missing") == nil)
        #expect(QueueTrackSelection(playerState: state, destinationIndex: 1, destinationTrackID: "wrong") == nil)
    }

    @Test("rejects a request after the queue changes")
    func rejectsChangedQueue() throws {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two"), makeSong("three")], currentIndex: 0)
        let selection = try #require(
            QueueTrackSelection(playerState: state, destinationIndex: 1, destinationTrackID: "two")
        )

        state.queue.swapAt(1, 2)

        #expect(selection.resolve(in: state) == nil)
    }

    @Test("rejects a request from a previous queue generation")
    func rejectsChangedGeneration() throws {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two")], currentIndex: 0)
        let selection = try #require(
            QueueTrackSelection(playerState: state, destinationIndex: 1, destinationTrackID: "two")
        )

        state.queueGeneration &+= 1

        #expect(selection.resolve(in: state) == nil)
    }

    @Test("keeps duplicate queue entries addressable by index")
    func supportsDuplicateSongs() throws {
        let duplicate = makeSong("duplicate")
        let state = makePlayerState(queue: [duplicate, duplicate], currentIndex: 0)
        let selection = try #require(
            QueueTrackSelection(playerState: state, destinationIndex: 1, destinationTrackID: "duplicate")
        )

        #expect(selection.resolve(in: state) == 1)
    }
}

@Suite("Queue upcoming rows")
@MainActor
struct QueueUpcomingRowTests {
    private func rows(_ state: PlayerState, limit: Int = .max) -> [QueueUpcomingRow] {
        QueueUpcomingRow.upcoming(in: state, occurrences: QueueUpcomingRow.occurrences(in: state.queue), limit: limit)
    }

    @Test("match the rows and selections the queue list captured before", arguments: [
        (["a", "b", "c", "d"], 0), (["a", "b", "a", "c", "a"], 1), (["a", "a", "a"], 0), (["a", "b"], 1),
        (["x", "y", "x", "y", "x"], 2), (["only"], 0),
    ])
    func matchLegacyCapture(ids: [String], currentIndex: Int) {
        let state = makePlayerState(queue: ids.map(makeSong), currentIndex: currentIndex)
        let legacy = LegacyHotPaths.captureQueue(state)
        let current = rows(state)
        #expect(current.map(\.id.songID) == legacy.map(\.id.songID))
        #expect(current.map(\.id.occurrence) == legacy.map(\.id.occurrence))
        #expect(current.map(\.id.generation) == legacy.map(\.id.generation))
        #expect(current.map(\.index) == legacy.map(\.selection.destinationIndex))
        #expect(current.map { $0.selection(in: state) } == legacy.map(\.selection))
    }

    @Test("are empty when the current track doesn't match its position, as before")
    func emptyWithoutAValidCurrentTrack() {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two")], currentIndex: 0)
        state.currentTrack = makeSong("elsewhere")
        #expect(rows(state).isEmpty)
        #expect(LegacyHotPaths.captureQueue(state).isEmpty)
        state.currentTrack = nil
        #expect(rows(state).isEmpty)
        state.currentTrack = state.queue[0]
        state.currentIndex = 5
        #expect(rows(state).isEmpty)
        #expect(LegacyHotPaths.captureQueue(state).isEmpty)
    }

    @Test("show a window of the upcoming songs")
    func window() {
        let state = makePlayerState(queue: (0..<10).map { makeSong("s\($0)") }, currentIndex: 2)
        #expect(rows(state, limit: 3).map(\.index) == [3, 4, 5])
        #expect(rows(state, limit: 100).map(\.index) == Array(3..<10))
    }

    @Test("can't act once the queue changes or the row is no longer upcoming")
    func rejectsStaleRows() throws {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two"), makeSong("three")], currentIndex: 0)
        let row = try #require(rows(state).last)
        #expect(row.selection(in: state)?.destinationIndex == 2)

        state.currentIndex = 2
        state.currentTrack = state.queue[2]
        #expect(row.selection(in: state) == nil)

        state.currentIndex = 0
        state.currentTrack = state.queue[0]
        state.queue = state.queue
        #expect(row.selection(in: state) == nil)
        #expect(rows(state).last?.selection(in: state)?.destinationIndex == 2)
    }
}

@Suite("Track swipe destinations")
@MainActor
struct TrackSwipeInteractionTests {
    @Test("exposes adjacent queue items")
    func exposesAdjacentItems() {
        let state = makePlayerState(
            queue: [makeSong("one"), makeSong("two"), makeSong("three")],
            currentIndex: 1
        )
        let interaction = TrackSwipeInteraction()

        #expect(interaction.destination(.previous, in: state)?.song.id == "one")
        #expect(interaction.destination(.next, in: state)?.song.id == "three")
    }

    @Test("respects queue boundaries and wraps next only in Repeat All")
    func respectsBoundaries() {
        let state = makePlayerState(queue: [makeSong("one"), makeSong("two")], currentIndex: 1)
        let interaction = TrackSwipeInteraction()

        #expect(interaction.destination(.next, in: state) == nil)

        state.repeatMode = .all
        #expect(interaction.destination(.next, in: state)?.song.id == "one")

        state.currentIndex = 0
        state.currentTrack = state.queue[0]
        #expect(interaction.destination(.previous, in: state) == nil)
    }
}

@MainActor
private func makePlayerState(queue: [DisplayableSong], currentIndex: Int) -> PlayerState {
    let state = PlayerState()
    state.queue = queue
    state.currentIndex = currentIndex
    state.currentTrack = queue[currentIndex]
    state.queueGeneration = 42
    return state
}

private func makeSong(_ id: String) -> DisplayableSong {
    DisplayableSong(
        id: id,
        title: id.capitalized,
        artist: "Artist",
        albumId: "album",
        albumName: "Album",
        artistId: "artist",
        genre: nil,
        duration: 180,
        trackNumber: 1,
        isDownloaded: false,
        coverArtId: id,
        audioFormat: "FLAC",
        replayGainTrackGain: nil,
        replayGainTrackPeak: nil,
        replayGainAlbumGain: nil,
        replayGainAlbumPeak: nil,
        replayGainBaseGain: nil,
        replayGainFallbackGain: nil
    )
}
