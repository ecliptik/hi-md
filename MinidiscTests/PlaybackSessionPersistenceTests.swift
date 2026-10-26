import Foundation
import SwiftData
import Testing
@testable import Minidisc

@Suite("Playback session persistence")
struct PlaybackSessionPersistenceTests {
    private func payload(_ queue: [DisplayableSong], index: Int, position: TimeInterval = 0,
                         revision: UInt64?) -> SessionPayload {
        SessionPayload(currentIndex: index, currentPosition: position, queue: queue, currentTrack: queue[index],
                       repeatMode: .off, queueRevision: revision)
    }

    @Test("A save with the stored queue revision moves the index and position and keeps the queue")
    func indexOnlySaveKeepsQueue() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        let queue = PerformanceFixtures.songs(50)
        await service.save(playerState: payload(queue, index: 0, revision: 7))
        // Same revision: the payload's queue is ignored, so a different array proves it isn't re-encoded.
        await service.save(playerState: payload(Array(queue.prefix(10)), index: 9, position: 42, revision: 7))
        let restored = try #require(await service.loadRestoredSession())
        #expect(restored.queue.map(\.id) == queue.map(\.id))
        #expect(restored.currentIndex == 9)
        #expect(restored.currentPosition == 42)
    }

    @Test("A new queue revision, or none, writes the queue again")
    func changedQueueIsWritten() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        let first = PerformanceFixtures.songs(20)
        let second = PerformanceFixtures.songs(30, seed: 99).map { song in
            DisplayableSong(id: "other-\(song.id)", title: song.title, artist: song.artist, albumId: song.albumId,
                            albumName: song.albumName, artistId: song.artistId, genre: nil, duration: song.duration,
                            trackNumber: song.trackNumber, isDownloaded: false, coverArtId: song.coverArtId,
                            audioFormat: nil, replayGainTrackGain: nil, replayGainTrackPeak: nil,
                            replayGainAlbumGain: nil, replayGainAlbumPeak: nil, replayGainBaseGain: nil,
                            replayGainFallbackGain: nil)
        }
        await service.save(playerState: payload(first, index: 1, revision: 1))
        await service.save(playerState: payload(second, index: 2, revision: 2))
        #expect(try #require(await service.loadRestoredSession()).queue.map(\.id) == second.map(\.id))
        await service.save(playerState: payload(first, index: 3, revision: nil))
        #expect(try #require(await service.loadRestoredSession()).queue.map(\.id) == first.map(\.id))
        await service.save(playerState: payload(second, index: 4, revision: nil))
        #expect(try #require(await service.loadRestoredSession()).queue.map(\.id) == second.map(\.id))
    }

    @Test("After the session is cleared, the next save writes the queue even with the old revision")
    func clearForgetsTheStoredRevision() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        let queue = PerformanceFixtures.songs(12)
        await service.save(playerState: payload(queue, index: 0, revision: 5))
        await service.clear()
        #expect(await service.loadRestoredSession() == nil)
        await service.save(playerState: payload(queue, index: 2, revision: 5))
        let restored = try #require(await service.loadRestoredSession())
        #expect(restored.queue.map(\.id) == queue.map(\.id))
        #expect(restored.currentIndex == 2)
    }

    @Test("A fresh service writes the queue even if the revision matches an earlier run's")
    func freshServiceWritesQueue() async throws {
        let container = try ModelContainer.session(inMemory: true)
        let queue = PerformanceFixtures.songs(8)
        await PlaybackSessionService(modelContainer: container).save(playerState: payload(queue, index: 0, revision: 3))
        let relaunched = PlaybackSessionService(modelContainer: container)
        let replacement = Array(queue.reversed())
        await relaunched.save(playerState: payload(replacement, index: 1, revision: 3))
        #expect(try #require(await relaunched.loadRestoredSession()).queue.map(\.id) == replacement.map(\.id))
    }
}

