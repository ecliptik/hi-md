import Foundation
import SwiftSonic

@Observable
@MainActor
final class SearchViewModel {
    /// Quiet period between the last keystroke and the actual server request.
    /// SearchView's `.task(id: query)` cancels the previous call on every change,
    /// so only the final query survives this delay.
    static let searchDebounce: Duration = .milliseconds(300)

    var searchResults: SearchResult3? {
        didSet { rank(force: true) }
    }
    var isSearching = false
    var searchError: UserFacingError?
    /// True only when neither the persistent catalogue index nor the server could answer,
    /// so the view falls back to downloaded tracks.
    var isOffline = false

    private(set) var playlists: [Playlist] = [] {
        didSet { rank(force: true) }
    }
    private(set) var isLoadingPlaylists = false
    private(set) var playlistError: UserFacingError?
    private(set) var resultsQuery = "" {
        didSet { rank(force: false) }
    }
    private var requestedQuery = "" {
        didSet { rank(force: false) }
    }
    private var requestGeneration = 0
    private var playlistGeneration = 0

    /// Ranked server results and playlists. Stored, not computed, because the view reads them
    /// several times per body; they're re-ranked only when the results, the playlists or the
    /// normalised query change.
    private(set) var matches: [LibrarySearchMatch] = []
    /// The songs in `matches`, in order, for multi-selection.
    private(set) var songMatches: [DisplayableSong] = []
    @ObservationIgnored private var rankedQuery = LibrarySearchQuery("")
    @ObservationIgnored private var offlineRanking: (snapshot: UUID, query: LibrarySearchQuery, matches: [LibrarySearchMatch])?

    /// Downloaded music ranked against `query`, reused while the snapshot and the normalised query
    /// stay the same. Safe to call from a view body: the memo isn't observed.
    func offlineMatches(query: String, in snapshot: OfflineBrowsingSnapshot) -> [LibrarySearchMatch] {
        let query = LibrarySearchQuery(query)
        if let offlineRanking, offlineRanking.snapshot == snapshot.identity, offlineRanking.query == query {
            return offlineRanking.matches
        }
        let matches = LibrarySearchRanking.rank(snapshot.searchEntries, query: query)
        offlineRanking = (snapshot.identity, query, matches)
        return matches
    }

    private func rank(force: Bool) {
        let text = resultsQuery.isEmpty ? requestedQuery : resultsQuery
        let query = LibrarySearchQuery(text)
        guard force || query != rankedQuery else { return }
        rankedQuery = query
        matches = LibrarySearchRanking.matches(query: text, results: searchResults, playlists: playlists)
        songMatches = matches.compactMap { match in
            if case .song(let song) = match { return song }
            return nil
        }
    }

    private let libraryService: any LibrarySearching
    private let playlistBrowser: (any PlaylistBrowsing)?
    private let serverState: ServerState
    private let debounce: Duration

    init(libraryService: any LibrarySearching, serverState: ServerState,
         playlistBrowser: (any PlaylistBrowsing)? = nil, debounce: Duration = SearchViewModel.searchDebounce) {
        self.libraryService = libraryService
        self.serverState = serverState
        self.playlistBrowser = playlistBrowser
        self.debounce = debounce
    }

    func loadPlaylists() async {
        guard let playlistBrowser else { return }
        playlistGeneration += 1
        let generation = playlistGeneration
        isLoadingPlaylists = true
        defer { if generation == playlistGeneration { isLoadingPlaylists = false } }
        do {
            let values = try await playlistBrowser.playlists()
            try Task.checkCancellation()
            guard generation == playlistGeneration else { return }
            playlists = values
            playlistError = nil
        } catch {
            guard generation == playlistGeneration, !Self.isCancellation(error) else { return }
            playlistError = UserFacingError.from(error)
        }
    }

    func search(query: String) async {
        requestGeneration += 1
        let generation = requestGeneration
        defer { if generation == requestGeneration { isSearching = false } }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        requestedQuery = trimmed
        guard !trimmed.isEmpty else {
            searchResults = nil
            searchError = nil
            isSearching = false
            isOffline = false
            resultsQuery = ""
            return
        }
        isOffline = false
        do {
            try await Task.sleep(for: debounce)
            guard generation == requestGeneration else { return }
            // Spinner reflects the actual in-flight request, not the debounce wait.
            isSearching = true
            searchError = nil
            let results = try await libraryService.search(trimmed)
            // Superseded between response and assignment — let the newer query win.
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            searchResults = results
            resultsQuery = trimmed
        } catch where Self.isCancellation(error) {
        } catch {
            guard generation == requestGeneration else { return }
            if serverState.isOnline {
                searchError = UserFacingError.from(error)
            } else {
                searchResults = nil
                searchError = nil
                isOffline = true
                resultsQuery = trimmed
            }
        }
    }

    /// True for task cancellation or a cancelled in-flight request — whether the
    /// URLError -999 surfaces raw or wrapped in `SwiftSonicError.network`.
    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let sse = error as? SwiftSonicError, case .network(let urlError) = sse, urlError.code == .cancelled { return true }
        return false
    }
}
