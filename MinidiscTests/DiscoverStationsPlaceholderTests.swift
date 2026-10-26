import Testing
import Foundation
import SwiftSonic
@testable import Minidisc

/// Listening history that answers only when the test releases it.
@MainActor
private final class GatedHistory: ListeningHistoryBrowsing {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var started = 0

    func recentlyPlayedAlbums(size: Int) async throws -> [AlbumID3] { await hold(); return [] }
    func mostPlayedAlbums(size: Int) async throws -> [AlbumID3] { await hold(); return [] }

    private func hold() async {
        started += 1
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@Suite("DiscoverViewModel — stations placeholder")
@MainActor
struct DiscoverStationsPlaceholderTests {
    @Test("the stations shelf holds its place only while the first load runs")
    func placeholderCoversOnlyTheFirstLoad() async {
        let history = GatedHistory()
        let vm = DiscoverViewModel(libraryService: history, recommendationService: RecommendationService(providers: []))
        #expect(!vm.isLoadingFirstStations)

        let load = Task { await vm.load() }
        for _ in 0..<1_000 where history.started < 2 { await Task.yield() }
        #expect(history.started == 2)
        #expect(vm.isLoadingFirstStations)

        history.release()
        await load.value
        // No history means no stations: the placeholder goes rather than staying empty.
        #expect(vm.stations.isEmpty)
        #expect(!vm.isLoadingFirstStations)
    }
}
