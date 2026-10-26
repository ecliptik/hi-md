import SwiftSonic
import SwiftUI

/// The main window: the sidebar, the selected section with the pages opened above it, the
/// lyrics and queue inspector on the right, and the player bar along the bottom.
struct MacRootView: View {
    let container: AppContainer
    let interface: MacInterface

    @AppStorage("minidisc.appTheme") private var theme: AppTheme = .system

    var body: some View {
        let navigator = interface.navigator
        let playback = interface.playback(for: container)
        let playlists = interface.playlists(for: container)
        @Bindable var bindableNavigator = navigator
        VStack(spacing: 0) {
            NavigationSplitView {
                MacSidebar(container: container)
            } detail: {
                NavigationStack(path: $bindableNavigator.path) {
                    MacSectionView(container: container, item: navigator.selection ?? .albums)
                        .navigationDestination(for: MacDestination.self) { destination in
                            MacDestinationView(container: container, destination: destination)
                        }
                }
            }
            .searchable(text: $bindableNavigator.searchText, placement: .toolbar, prompt: Text("Artists, Albums, Songs"))
            .inspector(isPresented: $bindableNavigator.isInspectorPresented) {
                MacInspector(container: container)
            }
            Divider()
            MacPlayerBar()
        }
        .frame(minWidth: 900, minHeight: 560)
        .environment(navigator)
        .environment(playback)
        .environment(playlists)
        .tint(Color.minidiscAccent)
        .preferredColorScheme(theme.colorScheme)
        .macPlaylistSheets(playlists, navigator: navigator)
        .onChange(of: navigator.searchText) { _, text in
            if !text.trimmingCharacters(in: .whitespaces).isEmpty, navigator.selection != .search {
                navigator.selection = .search
            }
        }
        .onAppear { MacSpaceKeyMonitor.shared.install(playback: playback) }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToDownloads)) { _ in
            navigator.selection = .downloads
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToPlaylist)) { note in
            guard let id = note.userInfo?["playlistId"] as? String else { return }
            navigator.selection = .playlist(id: id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistDeleted)) { _ in
            Task { await playlists.library.load() }
        }
        .onChange(of: container.playerState.currentTrack?.id) {
            // Lyrics can't follow a song that has none, such as a local file.
            if navigator.inspector == .lyrics, !playback.commands.canShowLyrics { navigator.inspector = .queue }
        }
    }
}

/// The root page of the selected sidebar item.
private struct MacSectionView: View {
    let container: AppContainer
    let item: MacSidebarItem

    var body: some View {
        if container.serverState.activeServer == nil {
            MacNoServerView()
        } else {
            switch item {
            case .search: MacSearchView(container: container)
            case .discover: MacDiscoverView(container: container)
            case .albums: MacAlbumsView(container: container)
            case .artists: MacArtistsView(container: container)
            case .songs: MacSongsView(container: container)
            case .genres: MacGenresView(container: container)
            case .recentlyAdded: MacRecentlyAddedView(container: container)
            case .favorites: MacFavoritesView(container: container)
            case .downloads: MacDownloadsView(container: container)
            case .playlist(let id): MacPlaylistDetailView(container: container, playlistID: id).id(id)
            }
        }
    }
}

/// A page pushed above the selected section.
private struct MacDestinationView: View {
    let container: AppContainer
    let destination: MacDestination

    var body: some View {
        switch destination {
        case .album(let id, let highlightedSongID):
            MacAlbumDetailView(container: container, albumID: id, highlightedSongID: highlightedSongID)
                .id(id)
        case .artist(let id, let name):
            MacArtistDetailView(container: container, artistID: id, artistName: name)
                .id(id)
        case .genre(let genre):
            MacGenreDetailView(container: container, genre: genre)
        case .playlist(let id):
            MacPlaylistDetailView(container: container, playlistID: id)
                .id(id)
        }
    }
}

private struct MacNoServerView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Server", systemImage: "server.rack")
        } description: {
            Text("No server configured. Please add a server in Settings.")
        } actions: {
            SettingsLink {
                Text("Open Settings")
            }
        }
    }
}
