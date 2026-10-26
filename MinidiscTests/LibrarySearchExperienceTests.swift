import Foundation
import Testing
import SwiftSonic
@testable import Minidisc

@Suite("Library search relevance and continuity", .timeLimit(.minutes(1)))
@MainActor
struct LibrarySearchExperienceTests {
    @Test("An exact song title outranks an artist prefix and an album substring")
    func exactResultFirst() throws {
        let results = try decode("""
        {"artist":[{"id":"a","name":"Lifehouse","albumCount":2}],
         "album":[{"id":"b","name":"A Day in the Life","songCount":1,"duration":180}],
         "song":[{"id":"c","title":"Life","isDir":false}]}
        """)
        let matches = LibrarySearchRanking.matches(query: "life", results: results, playlists: [])
        #expect(matches.first?.id == "song:c")
        #expect(matches.count == 3)
    }

    @Test("Artist and title tokens match regardless of order, case and accents")
    func combinedTokens() throws {
        let results = try decode("""
        {"song":[{"id":"c","title":"Jóga","artist":"Björk","isDir":false}]}
        """)
        let match = try #require(LibrarySearchRanking.matches(query: "BJORK joga", results: results, playlists: []).first)
        #expect(LibrarySearchRanking.score(match, query: "joga bjork") > 0)
    }

    @Test("Playlists are searchable by name and description, scoped separately from catalogue ids")
    func playlistMatches() throws {
        let playlists = [
            Playlist(id: "1", name: "Café du matin", songCount: 8, duration: 1200),
            Playlist(id: "2", name: "Evening", songCount: 4, duration: 500, comment: "Soft jazz"),
            Playlist(id: "3", name: "Metal", songCount: 5, duration: 1200)
        ]
        #expect(LibrarySearchRanking.matches(query: "cafe", results: nil, playlists: playlists).map(\.id) == ["playlist:1"])
        #expect(LibrarySearchRanking.matches(query: "jazz", results: nil, playlists: playlists).map(\.id) == ["playlist:2"])
        #expect(LibrarySearchRanking.matches(query: " ", results: nil, playlists: playlists).isEmpty)
    }

    @Test("Duplicate server results do not create duplicate row identities")
    func duplicateResults() throws {
        let results = try decode("""
        {"song":[{"id":"c","title":"Life","isDir":false},{"id":"c","title":"Life","isDir":false}]}
        """)
        #expect(LibrarySearchRanking.matches(query: "life", results: results, playlists: []).count == 1)
    }

    @Test("A late request cannot overwrite the newer result even if the service ignores cancellation")
    func lateResultIsDiscarded() async throws {
        let service = ControlledSearch()
        let vm = makeViewModel(service)
        let old = Task { await vm.search(query: "old") }
        await service.started("old")
        let new = Task { await vm.search(query: "new") }
        await service.started("new")
        service.finish("new", results: try decode("{}"))
        await new.value
        service.finish("old", results: try decode("{}"))
        await old.value
        #expect(vm.resultsQuery == "new")
        #expect(!vm.isSearching)
    }

    @Test("Existing results remain available and an older completion cannot hide the new loading state")
    func resultsRemainWhileUpdating() async throws {
        let service = ControlledSearch()
        let vm = makeViewModel(service)
        vm.searchResults = try decode("{\"song\":[{\"id\":\"saved\",\"title\":\"Saved\",\"isDir\":false}]}")
        let old = Task { await vm.search(query: "old") }
        await service.started("old")
        let new = Task { await vm.search(query: "new") }
        await service.started("new")
        #expect(vm.searchResults?.song?.first?.id == "saved")
        service.finish("old", results: try decode("{}"))
        await old.value
        #expect(vm.isSearching)
        #expect(vm.searchResults?.song?.first?.id == "saved")
        service.finish("new", results: try decode("{}"))
        await new.value
        #expect(!vm.isSearching)
    }

    // MARK: - Ranking is unchanged by scoring once

    static let equivalenceQueries = [
        "love", "LOVE", "lo", "l", "night", "nightfall", "blue night", "night blue", "the", "the love", "cafe", "Café",
        "bjork joga", "angstrom", "ångström", "deja vu", "rock n roll", "part ii", "live", "remix of", "mid", "sky ocean",
        "golden shadow echo", "zzz", " ", "", "  love  ", "song", "a",
    ]

    @Test("Online ranking keeps the order of scoring inside the comparator")
    func onlineOrderMatchesLegacy() throws {
        let results = try PerformanceFixtures.searchResult(artists: 50, albums: 100, songs: 200)
        let playlists = PerformanceFixtures.playlists(40)
        for query in Self.equivalenceQueries {
            let ranked = LibrarySearchRanking.matches(query: query, results: results, playlists: playlists).map(\.id)
            let legacy = LegacyHotPaths.onlineMatches(query: query, results: results, playlists: playlists).map(\.id)
            #expect(ranked == legacy, "query '\(query)'")
        }
    }

    @Test("Offline ranking over the snapshot's pre-normalised entries keeps the old order")
    func offlineOrderMatchesLegacy() {
        let snapshot = PerformanceFixtures.offlineSnapshot(songs: 1_500)
        for query in Self.equivalenceQueries {
            let ranked = LibrarySearchRanking.rank(snapshot.searchEntries, query: LibrarySearchQuery(query)).map(\.id)
            let legacy = LegacyHotPaths.offlineMatches(snapshot, searchQuery: query).map(\.id)
            #expect(ranked == legacy, "query '\(query)'")
        }
    }

    @Test("Scores match the old per-call normalisation")
    func scoresMatchLegacy() throws {
        let snapshot = PerformanceFixtures.offlineSnapshot(songs: 300)
        for query in Self.equivalenceQueries {
            for entry in snapshot.searchEntries {
                #expect(LibrarySearchRanking.score(entry.match, query: query) == LegacyHotPaths.score(entry.match, query: query))
            }
        }
    }

    @Test("Stored matches follow the results, the playlists and the query")
    func storedMatchesFollowInputs() async throws {
        let service = ControlledSearch()
        let vm = makeViewModel(service)
        #expect(vm.matches.isEmpty)
        let search = Task { await vm.search(query: "life") }
        await service.started("life")
        let results = try decode("""
        {"album":[{"id":"b","name":"A Day in the Life","songCount":1,"duration":180}],
         "song":[{"id":"c","title":"Life","isDir":false},{"id":"d","title":"Lifeline","isDir":false}]}
        """)
        service.finish("life", results: results)
        await search.value
        #expect(vm.matches.map(\.id) == ["song:c", "song:d", "album:b"])
        #expect(vm.songMatches.map(\.id) == ["c", "d"])
        vm.searchResults = nil
        #expect(vm.matches.isEmpty)
        #expect(vm.songMatches.isEmpty)
        await vm.search(query: "")
        #expect(vm.matches.isEmpty)
    }

    @Test("Offline matches are reused for the same snapshot and query, and redone for a new snapshot")
    func offlineMatchesFollowSnapshot() {
        let vm = makeViewModel(ControlledSearch())
        let first = PerformanceFixtures.offlineSnapshot(songs: 200)
        let ranked = vm.offlineMatches(query: "love", in: first).map(\.id)
        #expect(ranked == LegacyHotPaths.offlineMatches(first, searchQuery: "love").map(\.id))
        #expect(vm.offlineMatches(query: " Love ", in: first).map(\.id) == ranked)
        #expect(vm.offlineMatches(query: "night", in: first).map(\.id)
                == LegacyHotPaths.offlineMatches(first, searchQuery: "night").map(\.id))
        let second = OfflineBrowsingSnapshot(songs: Array(PerformanceFixtures.songs(200).prefix(20)))
        #expect(vm.offlineMatches(query: "love", in: second).map(\.id)
                == LegacyHotPaths.offlineMatches(second, searchQuery: "love").map(\.id))
    }

    private func decode(_ json: String) throws -> SearchResult3 {
        try JSONDecoder().decode(SearchResult3.self, from: Data(json.utf8))
    }

    private func makeViewModel(_ service: ControlledSearch) -> SearchViewModel {
        let state = ServerState()
        state.isOnline = true
        return SearchViewModel(libraryService: service, serverState: state, debounce: .zero)
    }
}

@MainActor
private final class ControlledSearch: LibrarySearching {
    private var pending: [String: CheckedContinuation<SearchResult3, Never>] = [:]
    private var waiters: [String: CheckedContinuation<Void, Never>] = [:]

    @MainActor
    func search(_ query: String) async throws -> SearchResult3 {
        await withCheckedContinuation { continuation in
            pending[query] = continuation
            waiters.removeValue(forKey: query)?.resume()
        }
    }

    func started(_ query: String) async {
        if pending[query] != nil { return }
        await withCheckedContinuation { waiters[query] = $0 }
    }

    func finish(_ query: String, results: SearchResult3) {
        pending.removeValue(forKey: query)?.resume(returning: results)
    }
}
