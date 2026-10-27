import Foundation
import Observation
import SwiftSonic

/// A list the Mac MiniPlayer's Library browser can show.
nonisolated enum LibraryBrowserLocation: Hashable, Sendable {
    /// Artists, Playlists and Favorites; its search field searches the whole library.
    case home
    case artists
    /// An artist's albums.
    case artist(id: String, name: String)
    /// An album's songs.
    case album(id: String, name: String)
    case playlists
    case playlist(id: String, name: String)
    /// The starred artists, albums and songs.
    case favorites
    /// The server's search results for the home page's search field.
    case search(String)

    /// The name of an album, artist or playlist page; the browser's own lists name themselves.
    var name: String? {
        switch self {
        case .artist(_, let name), .album(_, let name), .playlist(_, let name): name
        default: nil
        }
    }
}

/// One row of the Library browser: a list to open, an artist, an album, a playlist or a song.
nonisolated struct LibraryBrowserItem: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// One of the browser's own lists, from the home page.
        case list(LibraryBrowserLocation)
        case artist(id: String, albumCount: Int?)
        case album(id: String, artist: String?, artistID: String?, year: Int?)
        case playlist(Playlist)
        case song(DisplayableSong)
    }

    /// The heading a row sits under in Favorites and the search results.
    nonisolated enum Group: Hashable, Sendable {
        case artists, albums, songs
    }

    let id: String
    let name: String
    var coverArtID: String?
    let kind: Kind
    var group: Group?

    /// Where clicking the row goes; nil for a song, which plays.
    var destination: LibraryBrowserLocation? {
        switch kind {
        case .list(let location): location
        case .artist(let id, _): .artist(id: id, name: name)
        case .album(let id, _, _, _): .album(id: id, name: name)
        case .playlist(let playlist): .playlist(id: playlist.id, name: playlist.name)
        case .song: nil
        }
    }

    var song: DisplayableSong? {
        if case .song(let song) = kind { song } else { nil }
    }

    /// The home page: the lists to browse.
    static var homeItems: [LibraryBrowserItem] {
        [
            LibraryBrowserItem(id: "list-artists", name: String(localized: "Artists"), kind: .list(.artists)),
            LibraryBrowserItem(id: "list-playlists", name: String(localized: "Playlists"), kind: .list(.playlists)),
            LibraryBrowserItem(id: "list-favorites", name: String(localized: "Favorites"), kind: .list(.favorites)),
        ]
    }

    // MARK: From the server's records

    static func artists(_ artists: [ArtistID3], group: Group? = nil) -> [LibraryBrowserItem] {
        artists.map {
            LibraryBrowserItem(id: "artist-\($0.id)", name: $0.name, coverArtID: $0.coverArt ?? $0.id,
                               kind: .artist(id: $0.id, albumCount: $0.albumCount), group: group)
        }
    }

    /// An artist's albums, the newest first and those without a year last, as the artist's
    /// songs play.
    static func albums(_ albums: [AlbumID3], newestFirst: Bool = false, group: Group? = nil) -> [LibraryBrowserItem] {
        let ordered = newestFirst ? albums.sorted(by: newestFirstOrder) : albums
        return ordered.map {
            LibraryBrowserItem(id: "album-\($0.id)", name: $0.name, coverArtID: $0.coverArt ?? $0.id,
                               kind: .album(id: $0.id, artist: $0.artist, artistID: $0.artistId, year: $0.year),
                               group: group)
        }
    }

    private static func newestFirstOrder(_ lhs: AlbumID3, _ rhs: AlbumID3) -> Bool {
        switch (lhs.year, rhs.year) {
        case let (left?, right?) where left != right: return left > right
        case (nil, _?): return false
        case (_?, nil): return true
        default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func playlists(_ playlists: [Playlist]) -> [LibraryBrowserItem] {
        playlists.map {
            LibraryBrowserItem(id: "playlist-\($0.id)", name: $0.name, coverArtID: $0.coverArt, kind: .playlist($0))
        }
    }

    /// Songs in list order. A song can appear twice in a playlist, so each row's ID has its place.
    static func songs(_ songs: [DisplayableSong], group: Group? = nil) -> [LibraryBrowserItem] {
        songs.enumerated().map { index, song in
            LibraryBrowserItem(id: "song-\(index)-\(song.id)", name: song.title, coverArtID: song.coverArtId ?? song.id,
                               kind: .song(song), group: group)
        }
    }

    /// Favorites and search results: artists, then albums, then songs, each under its heading.
    static func grouped(artists: [ArtistID3], albums: [AlbumID3], songs: [DisplayableSong]) -> [LibraryBrowserItem] {
        Self.artists(artists, group: .artists) + Self.albums(albums, group: .albums) + Self.songs(songs, group: .songs)
    }
}

/// Where the Library browser's lists come from.
nonisolated protocol LibraryBrowserSource: Sendable {
    func items(at location: LibraryBrowserLocation) async throws -> [LibraryBrowserItem]
}

/// The lists from the server, through the library service.
nonisolated struct LibraryServiceBrowserSource: LibraryBrowserSource {
    typealias Library = LibrarySearching & AlbumBrowsing & ArtistBrowsing & PlaylistBrowsing & StarredBrowsing

    let library: any Library

    func items(at location: LibraryBrowserLocation) async throws -> [LibraryBrowserItem] {
        switch location {
        case .home:
            return LibraryBrowserItem.homeItems
        case .artists:
            return LibraryBrowserItem.artists(try await library.artists().flatMap(\.artist))
        case .artist(let id, _):
            return LibraryBrowserItem.albums(try await library.artist(id: id).album ?? [], newestFirst: true)
        case .album(let id, _):
            let songs = try await library.album(id: id).song ?? []
            return LibraryBrowserItem.songs(songs.map { DisplayableSong(from: $0) })
        case .playlists:
            return LibraryBrowserItem.playlists(try await library.playlists())
        case .playlist(let id, _):
            let songs = try await library.playlist(id: id).entry ?? []
            return LibraryBrowserItem.songs(songs.map { DisplayableSong(from: $0) })
        case .favorites:
            let starred = try await library.getStarred2()
            return LibraryBrowserItem.grouped(artists: starred.artist ?? [], albums: starred.album ?? [],
                                              songs: (starred.song ?? []).map { DisplayableSong(from: $0) })
        case .search(let query):
            let results = try await library.search(query)
            return LibraryBrowserItem.grouped(artists: results.artist ?? [], albums: results.album ?? [],
                                              songs: (results.song ?? []).map { DisplayableSong(from: $0) })
        }
    }
}

/// One list in the browser's back stack, with its own search text.
nonisolated struct LibraryBrowserPage: Identifiable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        case loading
        case loaded
        case failed(String)
    }

    let id = UUID()
    let location: LibraryBrowserLocation
    var phase: Phase
    var listing: FilteredListing<LibraryBrowserItem>

    init(location: LibraryBrowserLocation, phase: Phase = .loading, items: [LibraryBrowserItem] = []) {
        self.location = location
        self.phase = phase
        listing = FilteredListing(items: items, name: \.name)
    }
}

/// The Mac MiniPlayer's Library: a small browser for picking music without the main window.
/// Home lists Artists, Playlists and Favorites; clicking a row drills in (artist → albums →
/// songs) and Back returns, each list keeping its place and search text. The search field
/// narrows the list on screen with the same search as Winamp mode's Add Music browser; on the
/// home page it searches the whole library instead. Read-only: playing is up to the view.
@Observable
@MainActor
final class LibraryBrowserModel {
    /// Home first; the list on screen last.
    private(set) var pages: [LibraryBrowserPage] = [LibraryBrowserPage(location: .home, phase: .loaded,
                                                                       items: LibraryBrowserItem.homeItems)]
    /// The library search typed on the home page.
    private(set) var searchPage: LibraryBrowserPage?

    @ObservationIgnored private let source: any LibraryBrowserSource
    @ObservationIgnored private let searchDelay: Duration
    @ObservationIgnored private var loads: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// `searchDelay` waits for typing to pause before the home page searches the server.
    init(source: any LibraryBrowserSource, searchDelay: Duration = .milliseconds(300)) {
        self.source = source
        self.searchDelay = searchDelay
    }

    var current: LibraryBrowserPage { pages[pages.count - 1] }
    var location: LibraryBrowserLocation { current.location }
    var canGoBack: Bool { pages.count > 1 }
    /// The list Back returns to.
    var previousLocation: LibraryBrowserLocation? { pages.dropLast().last?.location }

    /// The search results while the home page's field has text, otherwise the list on screen.
    var shownPage: LibraryBrowserPage {
        if pages.count == 1, LibraryFilterText.isActive(current.listing.query), let searchPage { return searchPage }
        return current
    }

    var isSearchingLibrary: Bool { pages.count == 1 && LibraryFilterText.isActive(current.listing.query) }

    var rows: [LibraryBrowserItem] { shownPage.listing.shown }
    var phase: LibraryBrowserPage.Phase { shownPage.phase }

    /// The list has rows but the search left none, or the library search found nothing.
    var hasNoMatches: Bool {
        if isSearchingLibrary { return shownPage.phase == .loaded && shownPage.listing.items.isEmpty }
        return current.listing.hasNoMatches
    }

    /// The search field of the list on screen.
    var query: String {
        get { current.listing.query }
        set {
            pages[pages.count - 1].listing.query = newValue
            if pages.count == 1 { searchLibrary(for: newValue) }
        }
    }

    // MARK: Moving around

    /// Opens an artist, album, playlist or list; a song has nowhere to go.
    func open(_ item: LibraryBrowserItem) {
        guard let destination = item.destination else { return }
        open(destination)
    }

    func open(_ location: LibraryBrowserLocation) {
        guard location != .home else { return goHome() }
        let page = LibraryBrowserPage(location: location)
        pages.append(page)
        load(page.id)
    }

    func goBack() {
        guard canGoBack else { return }
        let page = pages.removeLast()
        loads.removeValue(forKey: page.id)?.cancel()
    }

    func goHome() {
        while canGoBack { goBack() }
    }

    /// Loads the list on screen again: Retry, or after the server or the favourites change.
    func reload() {
        if isSearchingLibrary {
            searchLibrary(for: current.listing.query, immediately: true)
        } else if current.location != .home {
            load(current.id)
        }
    }

    /// Back to the home page with nothing loaded, for another server.
    func reset() {
        goHome()
        searchTask?.cancel()
        searchPage = nil
        pages[0].listing.query = ""
    }

    // MARK: Playing

    /// What clicking a song plays: the songs of the list on screen, as the search leaves them,
    /// starting at that one.
    func songsToPlay(startingAt item: LibraryBrowserItem) -> (songs: [DisplayableSong], index: Int)? {
        let songRows = rows.filter { $0.song != nil }
        guard let index = songRows.firstIndex(where: { $0.id == item.id }) else { return nil }
        return (songRows.compactMap(\.song), index)
    }

    // MARK: Loading

    private func load(_ pageID: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let location = pages[index].location
        loads[pageID]?.cancel()
        if pages[index].listing.items.isEmpty { pages[index].phase = .loading }
        loads[pageID] = Task { [weak self, source] in
            let result: Result<[LibraryBrowserItem], any Error>
            do {
                result = .success(try await source.items(at: location))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            self?.finish(pageID, with: result)
        }
    }

    private func finish(_ pageID: UUID, with result: Result<[LibraryBrowserItem], any Error>) {
        loads[pageID] = nil
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        switch result {
        case .success(let items):
            let query = pages[index].listing.query
            pages[index].listing = FilteredListing(items: items, name: \.name)
            pages[index].listing.query = query
            pages[index].phase = .loaded
        case .failure(let error):
            guard !UserFacingError.isCancellation(error) else { return }
            pages[index].phase = .failed(UserFacingError.from(error).displayMessage)
        }
    }

    /// The home page's search, once typing pauses. The last results stay up while the next load.
    private func searchLibrary(for text: String, immediately: Bool = false) {
        searchTask?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchPage = nil
            return
        }
        if searchPage == nil { searchPage = LibraryBrowserPage(location: .search(query)) }
        let delay = immediately ? .zero : searchDelay
        searchTask = Task { [weak self, source] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let result: Result<[LibraryBrowserItem], any Error>
            do {
                result = .success(try await source.items(at: .search(query)))
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let items):
                searchPage = LibraryBrowserPage(location: .search(query), phase: .loaded, items: items)
            case .failure(let error):
                guard !UserFacingError.isCancellation(error) else { return }
                var page = searchPage ?? LibraryBrowserPage(location: .search(query))
                page.phase = .failed(UserFacingError.from(error).displayMessage)
                searchPage = page
            }
        }
    }

    /// Waits for the loads under way; for tests.
    func waitForLoads() async {
        while let task = searchTask ?? loads.values.first {
            await task.value
            if searchTask == task { searchTask = nil }
        }
    }
}
