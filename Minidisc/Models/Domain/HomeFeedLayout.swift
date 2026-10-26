import Foundation
import SwiftSonic

/// One of Home's shelves. The order of the cases is the order Home shows them in.
enum HomeShelf: Hashable, Sendable {
    case playlists
    case favoriteSongs
    case favoriteAlbums
    case recentlyPlayed
    case heavyRotation
    case rediscover
    case relevantAdditions
    case recentlyAdded
    /// One of the library's biggest genres, by name.
    case genre(String)
    /// Offline with nothing saved from the feed: the albums downloaded to this device.
    case offlineAlbums

    /// The shelf's heading. A genre's name is the server's, so it isn't translated.
    var title: String {
        switch self {
        case .playlists: String(localized: "Your Playlists")
        case .favoriteSongs: String(localized: "Your Favorite Songs")
        case .favoriteAlbums: String(localized: "Your Favorite Albums")
        case .recentlyPlayed: String(localized: "Recently Played")
        case .heavyRotation: String(localized: "In Heavy Rotation")
        case .rediscover: String(localized: "Rediscover")
        case .relevantAdditions: String(localized: "Recently Added from Your Artists")
        case .recentlyAdded: String(localized: "Recently Added")
        case .genre(let name): name
        case .offlineAlbums: String(localized: "Albums")
        }
    }
}

/// A row of Home, top to bottom.
enum HomeFeedRow: Identifiable {
    /// The "You're Offline" card.
    case offlineNotice
    /// Some sections failed to refresh; the rest is from the saved feed.
    case partialFailure
    /// A shelf still loading, held open so the shelves below don't jump when it arrives.
    case placeholder(HomeShelf)
    case playlists([Playlist])
    case favoriteSongs([Song])
    case albums(HomeShelf, [AlbumID3])

    var id: String {
        switch self {
        case .offlineNotice: "offline"
        case .partialFailure: "partialFailure"
        case .placeholder(let shelf): "placeholder.\(shelf.id)"
        case .playlists: HomeShelf.playlists.id
        case .favoriteSongs: HomeShelf.favoriteSongs.id
        case .albums(let shelf, _): shelf.id
        }
    }
}

extension HomeShelf: Identifiable {
    var id: String {
        switch self {
        case .playlists: "playlists"
        case .favoriteSongs: "favoriteSongs"
        case .favoriteAlbums: "favoriteAlbums"
        case .recentlyPlayed: "recentlyPlayed"
        case .heavyRotation: "heavyRotation"
        case .rediscover: "rediscover"
        case .relevantAdditions: "relevantAdditions"
        case .recentlyAdded: "recentlyAdded"
        case .genre(let name): "genre.\(name)"
        case .offlineAlbums: "offlineAlbums"
        }
    }
}

/// What Home shows: a full-page state, or its rows in order. The iPhone's Home and the Mac's lay
/// out the same rows, so both follow this.
enum HomeFeedState {
    /// Nothing to show yet and nothing loading has produced a row.
    case loading
    /// The feed failed with nothing saved to fall back on.
    case failed(UserFacingError)
    /// The server answered, but there is no music on it.
    case empty
    case rows([HomeFeedRow])
}

/// The feed's shelves, already filtered to what can be shown (offline, only what is on this
/// device).
struct HomeFeedContent {
    var playlists: [Playlist] = []
    var favorites = HomeFavorites()
    var recentlyPlayed: [AlbumID3] = []
    var heavyRotation: [AlbumID3] = []
    var rediscovery: [AlbumID3] = []
    var relevantAdditions: [AlbumID3] = []
    /// Recently added albums that aren't in `relevantAdditions`.
    var otherAdditions: [AlbumID3] = []
    var genres: [HomeFeedViewModel.GenreShelf] = []
    /// Offline, the albums on this device, shown when the feed has nothing saved.
    var offlineAlbums: [AlbumID3] = []
}

extension HomeFeedContent {
    /// The feed's shelves as the iPhone's Home shows them: offline, the favourites saved on this
    /// device, and only the albums and playlists it can play; genres left empty by that are dropped.
    init(feed: HomeFeedViewModel, container: AppContainer) {
        let isOnline = container.serverState.isOnline
        let snapshot = container.offlineLibrary.snapshot
        self.init(
            playlists: container.visiblePlaylists(feed.topPicks),
            favorites: isOnline ? feed.favorites : snapshot.favorites,
            recentlyPlayed: container.visibleAlbums(feed.recentlyPlayed),
            heavyRotation: container.visibleAlbums(feed.heavyRotation),
            rediscovery: container.visibleAlbums(feed.rediscovery),
            relevantAdditions: container.visibleAlbums(feed.relevantAdditions),
            otherAdditions: container.visibleAlbums(feed.otherAdditions),
            genres: feed.genreShelves.compactMap { shelf in
                let albums = container.visibleAlbums(shelf.albums)
                return albums.isEmpty ? nil : .init(name: shelf.name, albums: albums)
            },
            offlineAlbums: isOnline ? [] : snapshot.albums
        )
    }
}

enum HomeFeedLayout {
    /// Lays out Home the way the iPhone does.
    ///
    /// - Parameters:
    ///   - isEmpty: The feed has nothing at all, before filtering for offline.
    ///   - pending: Sections whose first answer hasn't arrived; an empty one gets a placeholder.
    static func state(
        isOnline: Bool,
        isLoading: Bool,
        isEmpty: Bool,
        error: UserFacingError?,
        hasPartialFailure: Bool,
        pending: Set<HomeFeedViewModel.Section>,
        content: HomeFeedContent
    ) -> HomeFeedState {
        if !isLoading, isEmpty, !isOnline {
            var rows: [HomeFeedRow] = [.offlineNotice]
            if !content.favorites.songs.isEmpty { rows.append(.favoriteSongs(content.favorites.songs)) }
            if !content.offlineAlbums.isEmpty { rows.append(.albums(.offlineAlbums, content.offlineAlbums)) }
            return .rows(rows)
        }
        if let error, isEmpty, !isLoading { return .failed(error) }
        if isEmpty, !isLoading { return .empty }

        var rows: [HomeFeedRow] = []
        if !isOnline {
            rows.append(.offlineNotice)
        } else if hasPartialFailure {
            rows.append(.partialFailure)
        }

        func placeholder(_ shelf: HomeShelf, when section: HomeFeedViewModel.Section, isShelfEmpty: Bool) {
            if isOnline, isShelfEmpty, pending.contains(section) { rows.append(.placeholder(shelf)) }
        }
        func albums(_ shelf: HomeShelf, _ albums: [AlbumID3]) {
            if !albums.isEmpty { rows.append(.albums(shelf, albums)) }
        }

        placeholder(.playlists, when: .playlists, isShelfEmpty: content.playlists.isEmpty)
        if !content.playlists.isEmpty { rows.append(.playlists(content.playlists)) }
        if !content.favorites.songs.isEmpty { rows.append(.favoriteSongs(content.favorites.songs)) }
        albums(.favoriteAlbums, content.favorites.albums)
        placeholder(.recentlyPlayed, when: .history, isShelfEmpty: content.recentlyPlayed.isEmpty)
        albums(.recentlyPlayed, content.recentlyPlayed)
        albums(.heavyRotation, content.heavyRotation)
        albums(.rediscover, content.rediscovery)
        albums(.relevantAdditions, content.relevantAdditions)
        placeholder(.recentlyAdded, when: .recent,
                    isShelfEmpty: content.relevantAdditions.isEmpty && content.otherAdditions.isEmpty)
        albums(.recentlyAdded, content.otherAdditions)
        for genre in content.genres { albums(.genre(genre.name), genre.albums) }

        // Still loading with nothing to hold a place for: show the spinner instead of a blank page.
        if isLoading, rows.isEmpty { return .loading }
        return .rows(rows)
    }

    /// The albums a shelf shows, for its See All page.
    static func albums(for shelf: HomeShelf, in content: HomeFeedContent) -> [AlbumID3] {
        switch shelf {
        case .favoriteAlbums: content.favorites.albums
        case .recentlyPlayed: content.recentlyPlayed
        case .heavyRotation: content.heavyRotation
        case .rediscover: content.rediscovery
        case .relevantAdditions: content.relevantAdditions
        case .recentlyAdded: content.otherAdditions
        case .genre(let name): content.genres.first { $0.name == name }?.albums ?? []
        case .offlineAlbums: content.offlineAlbums
        case .playlists, .favoriteSongs: []
        }
    }
}
