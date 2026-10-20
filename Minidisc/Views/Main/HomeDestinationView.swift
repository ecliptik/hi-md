import SwiftUI
import SwiftSonic

/// Resolves every `HomeDestination` for stacks that have no resolver of their own.
///
/// `NavigationLink(value:)` does nothing without a matching `navigationDestination`, and a
/// destination is only visible inside the stack that declares it. Screens that push
/// `HomeDestination` values are also hosted by the Discover tab and by sheets with their own
/// stack, so those stacks apply `resolvesHomeDestinations()`. Tab stacks that declare a richer
/// resolver with zoom transitions keep it: when a stack declares one twice, the one closest to the
/// root wins.
struct HomeDestinationView: View {
    let destination: HomeDestination
    @Environment(ArtworkImageCache.self) private var artworkImageCache

    var body: some View {
        switch destination {
        case .libraryAlbums:
            AlbumsListView()
        case .libraryArtists:
            ArtistListView()
        case .librarySongs:
            SongsListView()
        case .libraryPlaylists:
            PlaylistListView()
        case .libraryFavorites:
            FavoritesView()
        case .libraryDownloads:
            DownloadedView()
        case .album(let album):
            AlbumDetailView(album: album)
        case .artist(let artist):
            ArtistDetailView(artist: artist)
        case .playlist(let playlist):
            PlaylistDetailView(
                playlist: playlist,
                coverArtId: playlist.coverArt ?? playlist.id,
                initialCoverImage: artworkImageCache.cachedImage(for: playlist.coverArt ?? playlist.id)
            )
        case .downloadedAlbum(let display):
            AlbumDetailView(albumId: display.albumId, albumName: display.name, coverArtId: display.coverArtId, mode: .downloadedOnly)
        case .albumById(let id, let name, _, let coverArtId):
            AlbumDetailView(albumId: id, albumName: name, coverArtId: coverArtId)
        case .playlistById(let id, let name, let coverArtId):
            PlaylistDetailView(
                playlistId: id,
                name: name,
                coverArtId: coverArtId,
                initialCoverImage: artworkImageCache.cachedImage(for: coverArtId ?? id)
            )
        case .artistById(let id, let name, let coverArtId):
            ArtistDetailView(artist: ArtistID3(id: id, name: name, coverArt: coverArtId))
        case .artistBestOf(let id, let name, let coverArtId):
            ArtistBestOfView(artistId: id, artistName: name, coverArtId: coverArtId)
        case .recentlyAdded(let coverArtId):
            RecentlyAddedView(coverArtId: coverArtId)
        case .offlineArtist(let artist):
            OfflineArtistAlbumsView(artist: artist)
        case .offlineAlbum(let album):
            AlbumDetailView(albumId: album.albumId, albumName: album.albumName, coverArtId: album.coverArtId)
        }
    }
}

extension View {
    /// Makes `NavigationLink(value: HomeDestination)` work inside this view's navigation stack.
    func resolvesHomeDestinations() -> some View {
        navigationDestination(for: HomeDestination.self) { HomeDestinationView(destination: $0) }
    }
}
