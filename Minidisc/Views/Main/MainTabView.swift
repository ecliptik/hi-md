import SwiftUI

struct MainTabView: View {
    @Environment(\.appContainer) private var container
    @SceneStorage("minidisc.searchText") private var searchText = ""
    @State private var searchPath = NavigationPath()
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var playlistsPath = NavigationPath()
    @SceneStorage("minidisc.selectedTab") private var selectedTab: AppTab = .home
    @State private var playerPresentation = PlayerContainerConfiguration()
    @State private var playlistAddition = PlaylistAddition()
    @AppStorage("minidisc.appTheme") private var theme: AppTheme = .system

    private enum AppTab: String, Hashable { case home, discover, library, playlists, search }

    private var hasTrack: Bool {
        container?.playerState.currentTrack != nil || container?.playerState.isLiveStream == true
    }

    /// Widgets, Spotlight and Shortcuts open albums, playlists and artists through minidisc:// links.
    private func open(_ url: URL) {
        guard let destination = HomeDestination(url: url) else { return }
        playerPresentation.reset()
        selectedTab = .home
        homePath = NavigationPath([destination])
    }

    /// Opens the link `LinkRouter` is holding. In local-only mode there is no server to show it
    /// on, so it stays queued and opens once a server is connected.
    private func openPendingLink() {
        let hasServer = container?.serverState.activeServer != nil
        if let url = container?.linkRouter.take(hasActiveServer: hasServer) { open(url) }
    }

    var body: some View {
        @Bindable var playlistAddition = playlistAddition

        tabs
            .accessibilityHidden(playerPresentation.attachExpandedPlayer)
            .overlay(alignment: .topLeading) {
                if playerPresentation.attachExpandedPlayer {
                    PlayerContainer(configuration: playerPresentation)
                        .transition(.identity)
                }
            }
            .tabViewBottomAccessory(isEnabled: hasTrack && !playerPresentation.attachExpandedPlayer) {
                PlayerContainer(configuration: playerPresentation)
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .onChange(of: hasTrack) { _, hasTrack in
                if !hasTrack { playerPresentation.reset() }
            }
            .sheet(item: $playlistAddition.request) { request in
                AddToPlaylistSheet(request: request)
            }
            .environment(playlistAddition)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            if container?.serverState.activeServer != nil {
                Tab("Home", image: "HomeTabIcon", value: AppTab.home) {
                    NavigationStack(path: $homePath) {
                        HomeView()
                    }
                }

                Tab("Discover", systemImage: "square.grid.2x2.fill", value: AppTab.discover) {
                    NavigationStack(path: $discoverPath) {
                        DiscoverView()
                            .resolvesHomeDestinations()
                    }
                }

            }

            Tab("Library", systemImage: "music.note.square.stack.fill", value: AppTab.library) {
                NavigationStack(path: $libraryPath) {
                    if container?.serverState.activeServer == nil { LocalMusicView() }
                    else { LibraryView() }
                }
            }

            // Lidarr, when connected, is a Library tile so the bar keeps five tabs.
            if container?.serverState.activeServer != nil {
                Tab("Playlists", systemImage: "music.note.list", value: AppTab.playlists) {
                    NavigationStack(path: $playlistsPath) {
                        PlaylistListView()
                            .resolvesHomeDestinations()
                    }
                }
            }

            // Bare `Tab(value:role:)`: the search role renders its own detached button, glyph and
            // label. Passing a title and systemImage here draws a second glyph over the system's.
            if container?.serverState.activeServer != nil {
                Tab(value: AppTab.search, role: .search) {
                    NavigationStack(path: $searchPath) {
                        SearchView(searchQuery: $searchText, path: $searchPath)
                            .navigationTitle("Search")
                            .toolbarTitleDisplayMode(.inlineLarge)
                    }
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Artists, albums, songs, playlists…")
                }
            }
        }
        // A sidebar on iPad and the Mac; the bottom tab bar on iPhone.
        .tabViewStyle(.sidebarAdaptable)
        .onAppear { if container?.serverState.activeServer == nil { selectedTab = .library } }
        .accentColor(.minidiscAccent)
        .preferredColorScheme(theme.colorScheme)
        .onChange(of: container?.serverState.activeServer?.id) {
            homePath = NavigationPath()
            libraryPath = NavigationPath()
            discoverPath = NavigationPath()
            playlistsPath = NavigationPath()
            searchPath = NavigationPath()
            searchText = ""
            openPendingLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToLibrary)) { _ in
            playerPresentation.reset()
            libraryPath = NavigationPath()
            selectedTab = .library
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToDownloads)) { _ in
            playerPresentation.reset()
            libraryPath = NavigationPath([HomeDestination.libraryDownloads])
            selectedTab = .library
        }

        // Widget links, Spotlight results and Shortcuts "Open" actions, which can arrive during
        // launch. MinidiscApp queues every opened URL in the router.
        .onChange(of: container?.linkRouter.pending, initial: true) {
            openPendingLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToArtist)) { note in
            guard let id   = note.userInfo?["artistId"]   as? String,
                  let name = note.userInfo?["artistName"] as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            playerPresentation.reset()
            selectedTab = .home
            homePath.append(HomeDestination.artistById(id: id, name: name, coverArtId: coverArtId))
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToAlbum)) { note in
            guard let id   = note.userInfo?["albumId"]   as? String,
                  let name = note.userInfo?["albumName"] as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            playerPresentation.reset()
            selectedTab = .home
            homePath.append(HomeDestination.albumById(id: id, name: name, subtitle: "", coverArtId: coverArtId))
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscNavigateToPlaylist)) { note in
            guard let id   = note.userInfo?["playlistId"] as? String,
                  let name = note.userInfo?["name"]       as? String else { return }
            let coverArtId = note.userInfo?["coverArtId"] as? String
            playerPresentation.reset()
            selectedTab = .home
            homePath.append(HomeDestination.playlistById(id: id, name: name, coverArtId: coverArtId))
        }
    }
}
