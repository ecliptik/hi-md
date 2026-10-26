import Foundation
import SwiftSonic

@Observable
@MainActor
final class PlaylistListViewModel {
    var playlists: [Playlist] = []
    var isLoading = false
    var error: UserFacingError?

    private let libraryService: any PlaylistBrowsing & RecentlyAddedAlbumBrowsing & StarredBrowsing

    init(libraryService: any PlaylistBrowsing & RecentlyAddedAlbumBrowsing & StarredBrowsing) {
        self.libraryService = libraryService
    }

    var bestOfPlaylists: [ArtistBestOf] = []

    /// The newest album supplies the virtual playlist cover without fetching all its tracks.
    var newestAlbum: AlbumID3?

    /// Failure hides only Recently Added, leaving the main playlist list available.
    func loadRecentlyAdded() async {
        newestAlbum = (try? await libraryService.recentlyAddedAlbums(size: 1))?.first
    }

    /// Failure hides only derived best-of playlists, leaving the server playlist list available.
    func loadBestOf() async {
        guard let starred = try? await libraryService.getStarred2() else {
            bestOfPlaylists = []
            return
        }
        bestOfPlaylists = ArtistBestOf.all(in: starred.song ?? [])
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            playlists = try await libraryService.playlists()
        } catch {
            self.error = UserFacingError.from(error)
        }
        isLoading = false
    }

    // MARK: - Search

    /// Keeps the server order and matches name, owner and comment, which the playlist list already carries.
    static func filter(_ playlists: [Playlist], matching query: String) -> [Playlist] {
        playlists.filter { matches(query, in: [$0.name, $0.owner, $0.comment]) }
    }

    /// The derived rows match on the title they show.
    func bestOfPlaylists(matching query: String) -> [ArtistBestOf] {
        bestOfPlaylists.filter { Self.matches(query, in: [String(localized: "The best of \($0.artistName)")]) }
    }

    func newestAlbum(matching query: String) -> AlbumID3? {
        Self.matches(query, in: [String(localized: "Recently Added")]) ? newestAlbum : nil
    }

    /// Every query word must appear in one of the fields, folded like Add to Playlist so "energ" finds
    /// "Énergique". An empty query matches everything.
    static func matches(_ query: String, in fields: [String?]) -> Bool {
        let words = LibrarySearchRanking.normalized(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = fields.compactMap { $0 }.map(LibrarySearchRanking.normalized).joined(separator: " ")
        return words.allSatisfy { haystack.contains($0) }
    }
}
