import SwiftSonic
import SwiftUI

/// The main window: the sidebar, the selected section with the pages opened above it, the
/// lyrics and queue panel on the right, and the player bar along the bottom.
struct MacRootView: View {
    let container: AppContainer
    let interface: MacInterface

    @AppStorage("minidisc.appTheme") private var theme: AppTheme = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let navigator = interface.navigator
        let playback = interface.playback(for: container)
        let playlists = interface.playlists(for: container)
        @Bindable var bindableNavigator = navigator
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NavigationSplitView {
                    MacSidebar(container: container)
                } detail: {
                    MacDetailColumn(container: container)
                }
                .searchable(text: $bindableNavigator.searchText, placement: .toolbar, prompt: Text("Artists, Albums, Songs"))
                // The lyrics and queue panel, like the Music app's Playing Next. Read here, in the
                // root view's body, so showing and hiding it always redraws the window.
                if navigator.inspector != nil {
                    Divider()
                    MacInspector(container: container)
                        .frame(width: 320)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.smooth(duration: 0.25), value: navigator.inspector)
            Divider()
            MacPlayerBar()
        }
        .overlay {
            // The large player covers the whole window, player bar included, like the Music app's.
            if navigator.isNowPlayingShown {
                MacNowPlayingView(container: container)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: navigator.isNowPlayingShown)
        .toolbar(navigator.isNowPlayingShown ? .hidden : .automatic, for: .windowToolbar)
        .frame(minWidth: 900, minHeight: 560)
        .environment(interface)
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

/// The pages of the selected section. Its own view, so navigation changes redraw it: the split
/// view calls its detail closure outside the root view's update.
private struct MacDetailColumn: View {
    let container: AppContainer

    @Environment(MacNavigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.path) {
            MacSectionView(container: container, item: navigator.selection ?? .home)
                .navigationDestination(for: MacDestination.self) { destination in
                    MacDestinationView(container: container, destination: destination)
                }
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
            case .home: MacHomeView(container: container)
            case .search: MacSearchView(container: container)
            case .discover: MacDiscoverView(container: container)
            case .radio: MacRadioView(container: container)
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
        case .homeShelf(let shelf):
            MacHomeShelfView(container: container, shelf: shelf)
        case .recommendations:
            MacRecommendationsView(container: container)
        case .freshReleases:
            MacFreshReleasesView(container: container)
        case .freshRelease(let release):
            MacFreshReleaseDetailView(container: container, release: release)
        case .wrapped:
            MacWrappedView(container: container)
        case .wrappedRecap(let period):
            MacWrappedRecapView(container: container, period: period)
        case .radio:
            MacRadioView(container: container)
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
