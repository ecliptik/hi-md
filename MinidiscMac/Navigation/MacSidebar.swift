import SwiftSonic
import SwiftUI

/// The window's sidebar, laid out like the Music app's: Home, Search, Discover and Radio, the library,
/// then the user's playlists. Songs dragged onto a playlist are added to it.
struct MacSidebar: View {
    let container: AppContainer

    @Environment(MacNavigator.self) private var navigator
    @Environment(MacPlaylists.self) private var playlists

    var body: some View {
        @Bindable var navigator = navigator
        List(selection: $navigator.selection) {
            Section {
                Label("Home", systemImage: "house").sidebarItem(MacSidebarItem.home, navigator: navigator)
                Label("Search", systemImage: "magnifyingglass").sidebarItem(MacSidebarItem.search, navigator: navigator)
                Label("Discover", systemImage: "square.grid.2x2").sidebarItem(MacSidebarItem.discover, navigator: navigator)
                Label("Radio", systemImage: "antenna.radiowaves.left.and.right").sidebarItem(MacSidebarItem.radio, navigator: navigator)
            }

            Section("Library") {
                Label("Recently Added", systemImage: "clock").sidebarItem(MacSidebarItem.recentlyAdded, navigator: navigator)
                Label("Artists", systemImage: "music.microphone").sidebarItem(MacSidebarItem.artists, navigator: navigator)
                Label("Albums", image: MinidiscSymbol.album).sidebarItem(MacSidebarItem.albums, navigator: navigator)
                Label("Songs", systemImage: "music.note").sidebarItem(MacSidebarItem.songs, navigator: navigator)
                Label("Genres", systemImage: "guitars").sidebarItem(MacSidebarItem.genres, navigator: navigator)
                Label("Favorites", systemImage: "heart").sidebarItem(MacSidebarItem.favorites, navigator: navigator)
                Label("Downloads", systemImage: "arrow.down.circle").sidebarItem(MacSidebarItem.downloads, navigator: navigator)
            }

            Section {
                ForEach(playlists.playlists) { playlist in
                    playlistRow(playlist)
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button("New Playlist…", systemImage: "plus") { playlists.requestNewPlaylist() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .disabled(!playlists.canEdit)
                        .help("New Playlist")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        .task(id: container.serverState.accessSnapshot) { await playlists.library.load() }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscPlaylistsChanged)) { _ in
            Task { await playlists.library.load() }
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        Label {
            Text(playlist.name)
                .lineLimit(1)
        } icon: {
            Image(systemName: "music.note.list")
        }
        .sidebarItem(.playlist(id: playlist.id), navigator: navigator)
        .dropDestination(for: MacSongDrag.self) { items, _ in
            guard playlists.canEdit else { return false }
            playlists.add(items.map(\.song), to: playlist)
            return true
        }
        .contextMenu { MacPlaylistMenu(playlist: playlist) }
    }
}

private extension View {
    /// A sidebar row: selecting it shows its section, and clicking it again while it's selected
    /// goes back to the section's own page.
    func sidebarItem(_ item: MacSidebarItem, navigator: MacNavigator) -> some View {
        tag(item).simultaneousGesture(TapGesture().onEnded { navigator.clickSidebar(item) })
    }
}

/// The context menu for a playlist, in the sidebar and on Home.
struct MacPlaylistMenu: View {
    let playlist: Playlist
    /// Runs before Rename and Delete, whose sheets show on the main window, so a window other
    /// than the main one (the MiniPlayer) can bring it forward first.
    var beforeShowingSheet: (() -> Void)? = nil

    @Environment(MacPlayback.self) private var playback
    @Environment(MacPlaylists.self) private var playlists

    var body: some View {
        Button("Play", systemImage: "play") { playback.playPlaylist(id: playlist.id) }
        Button("Shuffle", systemImage: "shuffle") { playback.playPlaylist(id: playlist.id, shuffled: true) }
        Divider()
        Button("Download", systemImage: "arrow.down.circle") { playback.downloadPlaylist(id: playlist.id) }
            .disabled(!playlists.canEdit)
        Divider()
        Button("Rename…") {
            beforeShowingSheet?()
            playlists.renaming = playlist
        }
            .disabled(!playlists.canEdit)
        Button("Delete Playlist…", role: .destructive) {
            beforeShowingSheet?()
            playlists.deleting = playlist
        }
            .disabled(!playlists.canEdit)
    }
}
