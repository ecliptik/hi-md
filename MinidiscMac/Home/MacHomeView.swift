import SwiftSonic
import SwiftUI

/// Home: the iPhone's Home feed as Music-style shelves. Your Playlists, Your Favorite Songs, Your
/// Favorite Albums, Recently Played, In Heavy Rotation, Rediscover, the recent additions and the
/// biggest genres, in the iPhone's order. Each heading opens its full list.
struct MacHomeView: View {
    let container: AppContainer

    @Environment(MacInterface.self) private var interface
    @Environment(MacNavigator.self) private var navigator
    @AppStorage("minidisc.mac.favoritesKind") private var favoritesKind: MacFavoritesView.Kind = .songs

    private struct LoadIdentity: Hashable {
        let serverID: UUID?
        let isOnline: Bool
    }

    var body: some View {
        let home = interface.homeFeed(for: container)
        Group {
            if let home {
                content(home)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await home?.reload() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(home == nil || home?.feed.isLoading == true)
            }
        }
        .task(id: LoadIdentity(serverID: container.serverState.activeServer?.id, isOnline: container.serverState.isOnline)) {
            await home?.loadIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistsChanged)) { _ in
            Task { await home?.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscFavoritesChanged)) { _ in
            Task { await home?.reload() }
        }
    }

    @ViewBuilder
    private func content(_ home: MacHomeFeed) -> some View {
        switch home.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Unable to Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.displayMessage)
            } actions: {
                Button("Try Again") { Task { await home.reload() } }
            }
        case .empty:
            ContentUnavailableView {
                Label("No music yet", systemImage: "music.note.list")
            } description: {
                Text("Add some music to your server to get started")
            }
        case .rows(let rows):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ForEach(rows) { row in
                        self.row(row, home: home)
                    }
                }
                .padding(.vertical, 20)
            }
        }
    }

    @ViewBuilder
    private func row(_ row: HomeFeedRow, home: MacHomeFeed) -> some View {
        switch row {
        case .offlineNotice:
            MacOfflineNotice(container: container)
                .padding(.horizontal, MacShelfMetrics.margin)
        case .partialFailure:
            HStack(spacing: 12) {
                Label("Some sections could not be refreshed. Your saved library is still available.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { Task { await home.reload() } }
            }
            .padding(.horizontal, MacShelfMetrics.margin)
        case .placeholder(let shelf):
            MacShelfPlaceholder(title: shelf.title,
                                side: shelf == .playlists ? MacShelfMetrics.playlistSide : MacShelfMetrics.albumSide)
        case .playlists(let playlists):
            MacShelf(title: HomeShelf.playlists.title, onOpen: { navigator.show(.homeShelf(.playlists)) }) {
                ForEach(playlists.prefix(MacShelfMetrics.previewLimit)) { playlist in
                    MacPlaylistTile(playlist: playlist)
                }
            }
        case .favoriteSongs(let songs):
            MacSongShelf(title: HomeShelf.favoriteSongs.title, songs: songs.map { DisplayableSong(from: $0) },
                         onOpen: { showFavorites(.songs) })
        case .albums(let shelf, let albums):
            MacShelf(title: shelf.title, onOpen: { open(shelf) }) {
                ForEach(albums.prefix(MacShelfMetrics.previewLimit)) { album in
                    MacAlbumTile(album: album)
                        .frame(width: MacShelfMetrics.albumSide)
                }
            }
        }
    }

    /// Favourites open the library's Favorites; the other shelves open their own full list.
    private func open(_ shelf: HomeShelf) {
        if shelf == .favoriteAlbums {
            showFavorites(.albums)
        } else {
            navigator.show(.homeShelf(shelf))
        }
    }

    private func showFavorites(_ kind: MacFavoritesView.Kind) {
        favoritesKind = kind
        navigator.selection = .favorites
    }
}

/// A Home shelf's full list: its albums in a grid, or for Your Playlists, the playlists.
struct MacHomeShelfView: View {
    let container: AppContainer
    let shelf: HomeShelf

    @Environment(MacInterface.self) private var interface

    private let playlistColumns = [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        let home = interface.homeFeed(for: container)
        let content = home?.content ?? HomeFeedContent()
        Group {
            if shelf == .playlists {
                MacLoadingState(isLoading: home?.feed.isLoading ?? true, isEmpty: content.playlists.isEmpty,
                                emptyTitle: "No Playlists", emptySystemImage: "music.note.list") {
                    ScrollView {
                        LazyVGrid(columns: playlistColumns, alignment: .leading, spacing: 24) {
                            ForEach(content.playlists) { playlist in
                                MacPlaylistTile(playlist: playlist, side: 180)
                            }
                        }
                        .padding(20)
                    }
                }
            } else {
                let albums = HomeFeedLayout.albums(for: shelf, in: content)
                MacLoadingState(isLoading: home?.feed.isLoading ?? true, isEmpty: albums.isEmpty,
                                emptyTitle: "No Albums", emptySystemImage: "square.stack") {
                    ScrollView {
                        MacAlbumGrid(albums: albums)
                            .padding(20)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: shelf.title))
        .task { await home?.loadIfNeeded() }
    }
}

/// Home's "You're Offline" card: what can play on this Mac, and Turn Off Offline Mode when that is
/// why.
struct MacOfflineNotice: View {
    let container: AppContainer

    @Environment(MacNavigator.self) private var navigator

    var body: some View {
        let isManual = container.serverState.isOfflineModeEnabled
        let songCount = container.offlineLibrary.snapshot.songs.count
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.minidiscAccent)
                .frame(width: 40, height: 40)
                .background(Color.minidiscAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(isManual ? LocalizedStringKey("Offline Mode") : LocalizedStringKey("You're Offline"))
                    .font(.headline)
                Group {
                    if container.offlineLibrary.isLoading && songCount == 0 {
                        Text("Loading…")
                    } else if songCount > 0 {
                        Text("\(songCount) songs available offline")
                    } else {
                        Text("No music saved on this device.")
                    }
                }
                .foregroundStyle(.secondary)
                Text("While offline, the app only shows content available on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 12)
            if songCount > 0 {
                Button("Downloads") { navigator.selection = .downloads }
            }
            if isManual {
                Button("Turn Off Offline Mode") { container.serverState.isOfflineModeEnabled = false }
                    .buttonStyle(.borderedProminent)
                    .tint(AppearanceSettings.shared.accent.fillColor)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}
