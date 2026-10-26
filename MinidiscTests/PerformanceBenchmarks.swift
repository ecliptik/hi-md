import Foundation
import SwiftData
import SwiftSonic
import Testing
import UIKit
@testable import Minidisc

/// Opt-in timings for the hot paths in `docs/audits/perf-2026-10-25.md`. Normal runs skip them; run
///
///     TEST_RUNNER_MINIDISC_BENCH=1 xcodebuild test ... -only-testing:MinidiscTests/PerformanceBenchmarks
///
/// Each line printed as `[BENCH] name | scale | median …` is one warm-up run followed by the median
/// of several timed runs. Simulator numbers are indicative only.
@Suite("Performance benchmarks", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["MINIDISC_BENCH"] == "1"))
@MainActor
struct PerformanceBenchmarks {
    // MARK: - 1. Search ranking

    @Test func offlineSearchRanking() {
        let snapshot = PerformanceFixtures.offlineSnapshot()
        let items = snapshot.songs.count + snapshot.albums.count + snapshot.artists.count + snapshot.playlists.count
        let vm = SearchViewModel(libraryService: FixedSearch(results: nil), serverState: ServerState())
        for query in ["love", "blue night", "ångström"] {
            Bench.measure("search.offline.legacy '\(query)'", scale: "\(items) items") {
                LegacyHotPaths.offlineMatches(snapshot, searchQuery: query)
            }
            Bench.measure("search.offline.rank '\(query)'", scale: "\(items) items") {
                LibrarySearchRanking.rank(snapshot.searchEntries, query: LibrarySearchQuery(query))
            }
            // A body pass that doesn't change the query or the snapshot reuses the ranking.
            Bench.measure("search.offline.body '\(query)'", scale: "\(items) items") {
                vm.offlineMatches(query: query, in: snapshot)
            }
        }
        // The one-off cost moved into loading the snapshot, off the MainActor.
        let matches = snapshot.songs.map(LibrarySearchMatch.song) + snapshot.albums.map(LibrarySearchMatch.album)
            + snapshot.artists.map(LibrarySearchMatch.artist) + snapshot.playlists.map(LibrarySearchMatch.playlist)
        Bench.measure("search.offline.index-build", scale: "\(items) items", runs: 5) {
            matches.map(LibrarySearchEntry.init)
        }
    }

    @Test func onlineSearchRanking() async throws {
        let results = try PerformanceFixtures.searchResult(artists: 50, albums: 100, songs: 200)
        let playlists = PerformanceFixtures.playlists(40)
        for query in ["love", "blue night"] {
            Bench.measure("search.online.legacy.rank '\(query)'", scale: "350 results + 40 playlists") {
                LegacyHotPaths.onlineMatches(query: query, results: results, playlists: playlists)
            }
            Bench.measure("search.online.current.rank '\(query)'", scale: "350 results + 40 playlists") {
                LibrarySearchRanking.matches(query: query, results: results, playlists: playlists)
            }
            // The view model now ranks once when the results arrive; a body pass reads stored arrays.
            let state = ServerState()
            state.isOnline = true
            let vm = SearchViewModel(libraryService: FixedSearch(results: results), serverState: state, debounce: .zero)
            await vm.search(query: query)
            #expect(!vm.matches.isEmpty)
            Bench.measure("search.online.body '\(query)'", scale: "350 results + 40 playlists") {
                (vm.matches, vm.songMatches)
            }
            // The body read `matches` once for the list and once more through `selectableSongs`.
            Bench.measure("search.online.legacy.body '\(query)'", scale: "350 results + 40 playlists") {
                let matches = LegacyHotPaths.onlineMatches(query: query, results: results, playlists: playlists)
                let songs = LegacyHotPaths.onlineMatches(query: query, results: results, playlists: playlists)
                    .compactMap { if case .song(let song) = $0 { song } else { nil } }
                return (matches, songs)
            }
        }
    }

    // MARK: - 2. Queue rows

    @Test(arguments: [50_000, 200_000])
    func queueSnapshot(count: Int) {
        let state = PlayerState()
        state.queue = PerformanceFixtures.songs(count)
        state.currentIndex = 10
        state.currentTrack = state.queue[10]
        Bench.measure("queue.capture.legacy", scale: "\(count) songs", runs: 5) {
            LegacyHotPaths.captureQueue(state)
        }
        // A new or edited queue: occurrence counts once, then the first page of rows.
        Bench.measure("queue.rows.queueChange", scale: "\(count) songs", runs: 5) {
            QueueUpcomingRow.upcoming(in: state, occurrences: QueueUpcomingRow.occurrences(in: state.queue),
                                      limit: InlineQueueList.pageSize)
        }
        // A skip: the counts are reused, and only the page after the new current track is built.
        let occurrences = QueueUpcomingRow.occurrences(in: state.queue)
        Bench.measure("queue.rows.skip", scale: "\(count) songs", runs: 9) {
            state.currentIndex += 1
            state.currentTrack = state.queue[state.currentIndex]
            return QueueUpcomingRow.upcoming(in: state, occurrences: occurrences, limit: InlineQueueList.pageSize)
        }
    }

    // MARK: - 3. Placeholder detection

    @Test func placeholderDetection() {
        for (name, side) in [("thumb", 240), ("hero", 1200)] {
            let cover = PerformanceFixtures.cover(side: side)
            Bench.measure("placeholder.legacy.\(name)", scale: "\(side) px, ×20 covers", runs: 9) {
                for _ in 0..<20 { _ = LegacyHotPaths.isServerPlaceholder(cover) }
            }
            Bench.measure("placeholder.current.\(name)", scale: "\(side) px, ×20 covers", runs: 9) {
                for _ in 0..<20 { _ = ServerPlaceholderArtwork.matches(cover) }
            }
        }
    }

    // MARK: - 5. ForEach over enumerated songs

    @Test(arguments: [5_000, 200_000])
    func enumeratedRows(count: Int) {
        let songs = PerformanceFixtures.songs(count)
        Bench.measure("foreach.array-enumerated", scale: "\(count) songs") {
            var hasher = Hasher()
            for element in Array(songs.enumerated()) { hasher.combine(element.element.id) }
            return hasher.finalize()
        }
        Bench.measure("foreach.lazy-enumerated", scale: "\(count) songs") {
            var hasher = Hasher()
            for element in songs.enumerated() { hasher.combine(element.element.id) }
            return hasher.finalize()
        }
    }

    // MARK: - 6. Song selection

    @Test func songSelectionDerivation() {
        let request = SongSelectionRequest(songs: PerformanceFixtures.songs(200_000))
        for query in ["", "love"] {
            // The body read `visibleSongs` three times, each re-deriving `songs`, plus a Set for the label.
            Bench.measure("selection.legacy.body '\(query)'", scale: "200000 songs", runs: 3) {
                let disabled = LegacyHotPaths.visibleSelectionSongs(request, query: query).isEmpty
                let label = Set<String>().isSuperset(of: LegacyHotPaths.visibleSelectionSongs(request, query: query).map(\.id))
                let rows = LegacyHotPaths.visibleSelectionSongs(request, query: query)
                return (disabled, label, rows.count)
            }
        }
        // The sheet now derives once per request and query; a later body pass, such as after a tap,
        // reads the cached result and checks the label against its ID set.
        let collection = SongSelectionCollection(request.songs)
        Bench.measure("selection.open", scale: "200000 songs", runs: 3) {
            SongSelectionCollection(request.songs).filtered(by: "")
        }
        Bench.measure("selection.firstQuery 'love'", scale: "200000 songs", runs: 3) {
            SongSelectionCollection(request.songs).filtered(by: "love")
        }
        _ = collection.filtered(by: "love")
        Bench.measure("selection.nextQuery 'blue'", scale: "200000 songs", runs: 3) {
            collection.filtered(by: "blue")
        }
        let cached = collection.filtered(by: "")
        var selected = cached.ids
        selected.insert("after Select All, plus one")
        Bench.measure("selection.body (tap, all selected)", scale: "200000 songs", runs: 7) {
            selected.isSuperset(of: cached.ids)
        }
    }

    // MARK: - 7. Track change

    @Test func trackChangeQueueWork() {
        let state = PlayerState()
        state.queue = PerformanceFixtures.songs(20_000)
        state.currentIndex = 100
        state.currentTrack = state.queue[100]
        let tracks = state.queue
        Bench.measure("trackchange.legacy.isNewQueue", scale: "20000-song queue", runs: 9) {
            LegacyHotPaths.isNewQueue(tracks: tracks, state: state)
        }
        Bench.measure("trackchange.legacy.autoExtendRead", scale: "20000-song queue", runs: 9) {
            LegacyHotPaths.autoExtendRead(state)
        }
    }

    @Test func sessionSave() async throws {
        let service = PlaybackSessionService(modelContainer: try ModelContainer.session(inMemory: true))
        let queue = PerformanceFixtures.songs(20_000)
        var index = 0
        await Bench.measureAsync("session.save.indexOnly", scale: "20000-song queue", runs: 7) {
            index += 1
            await service.save(playerState: SessionPayload(currentIndex: index, currentPosition: 0, queue: queue,
                                                           currentTrack: queue[index], repeatMode: .off))
        }
    }

    // MARK: - 8. Memory

    @Test func lidarrRetainedBytes() {
        let store = LidarrImageStore()
        let images = PerformanceFixtures.sharedBufferImages(count: 300, side: 1000)
        for (index, image) in images.enumerated() { store.store(image, for: "cover-\(index)") }
        let retained = (0..<images.count).compactMap { store.image(for: "cover-\($0)") }
        Bench.report("lidarr.retained", scale: "300 covers of 1000 px",
                     value: "\(retained.count) images, \(Bench.megabytes(retained.map(PerformanceFixtures.decodedBytes).reduce(0, +))) MB")
    }

    @Test func artworkCacheRetainedBytes() async {
        let heroes = PerformanceFixtures.sharedBufferImages(count: 1, side: 1200)[0]
        let thumbs = PerformanceFixtures.sharedBufferImages(count: 1, side: 240)[0]
        let cache = ArtworkImageCache(
            revalidationStore: CoverRevalidationStore(fileURL: URL.temporaryDirectory.appendingPathComponent("bench-\(UUID())")),
            coverArtURLProvider: { id, size in URL(string: "https://example.invalid/\(id)/\(size)") },
            dataLoader: { request in
                (Data([1]), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                            headerFields: ["Cache-Control": "max-age=31536000"])!)
            },
            imageDecoder: { _, size in size >= 1200 ? heroes : thumbs }
        )
        cache.persistCoversEnabled = false
        for index in 0..<110 { await cache.load(coverArtId: "al-\(index)", tier: .hero) }
        for index in 0..<110 { await cache.load(coverArtId: "al-\(index)", tier: .thumb) }
        for index in 110..<150 { await cache.load(coverArtId: "al-\(index)", tier: .hero) }
        let retained = (0..<150).flatMap { index in
            [ArtworkTier.thumb, .hero].compactMap { cache.cachedImage(for: "al-\(index)", tier: $0) }
        }
        Bench.report("artwork.retained", scale: "110 heroes, 110 thumbs, 40 heroes",
                     value: "\(retained.count) images, \(Bench.megabytes(retained.map(PerformanceFixtures.decodedBytes).reduce(0, +))) MB")
    }
}

// MARK: - Harness

@MainActor
enum Bench {
    private static let clock = ContinuousClock()

    /// One warm-up run, then the median of `runs` timed runs.
    @discardableResult
    static func measure<T>(_ name: String, scale: String, runs: Int = 7, _ body: () -> T) -> Duration {
        blackHole(body())
        var samples: [Duration] = []
        for _ in 0..<runs {
            let start = clock.now
            let value = body()
            samples.append(clock.now - start)
            blackHole(value)
        }
        return record(name, scale: scale, samples: samples)
    }

    @discardableResult
    static func measureAsync(_ name: String, scale: String, runs: Int = 7, _ body: () async -> Void) async -> Duration {
        await body()
        var samples: [Duration] = []
        for _ in 0..<runs {
            let start = clock.now
            await body()
            samples.append(clock.now - start)
        }
        return record(name, scale: scale, samples: samples)
    }

    static func report(_ name: String, scale: String, value: String) {
        print("[BENCH] \(name) | \(scale) | \(value)")
    }

    static func megabytes(_ bytes: Int) -> String {
        (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(1)))
    }

    private static func record(_ name: String, scale: String, samples: [Duration]) -> Duration {
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        report(name, scale: scale, value: "median \(milliseconds(median)) ms (min \(milliseconds(sorted[0])), max \(milliseconds(sorted[sorted.count - 1])), n=\(samples.count))")
        return median
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1_000 + Double(attoseconds) / 1e15
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    @inline(never)
    static func blackHole<T>(_ value: T) {
        withExtendedLifetime(value) {}
    }
}

nonisolated private final class FixedSearch: LibrarySearching {
    let results: SearchResult3?
    init(results: SearchResult3?) { self.results = results }
    func search(_ query: String) async throws -> SearchResult3 {
        guard let results else { throw URLError(.notConnectedToInternet) }
        return results
    }
}
