import SwiftSonic
import SwiftUI

/// The window's sidebar, laid out like the Music app's: Home, Search and Recommended for You, the library,
/// then the user's playlists. Songs dragged onto a playlist are added to it.
struct MacSidebar: View {
    let container: AppContainer

    @Environment(MacNavigator.self) private var navigator
    @Environment(MacPlaylists.self) private var playlists

    var body: some View {
        @Bindable var navigator = navigator
        List(selection: $navigator.selection) {
            Section {
                Label("Home", systemImage: "house").tag(MacSidebarItem.home)
                Label("Search", systemImage: "magnifyingglass").tag(MacSidebarItem.search)
                Label("Recommended for You", systemImage: "sparkles").tag(MacSidebarItem.discover)
            }

            Section("Library") {
                Label("Recently Added", systemImage: "clock").tag(MacSidebarItem.recentlyAdded)
                Label("Artists", systemImage: "music.microphone").tag(MacSidebarItem.artists)
                Label("Albums", systemImage: "square.stack").tag(MacSidebarItem.albums)
                Label("Songs", systemImage: "music.note").tag(MacSidebarItem.songs)
                Label("Genres", systemImage: "guitars").tag(MacSidebarItem.genres)
                Label("Favorites", systemImage: "heart").tag(MacSidebarItem.favorites)
                Label("Downloads", systemImage: "arrow.down.circle").tag(MacSidebarItem.downloads)
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
        .tag(MacSidebarItem.playlist(id: playlist.id))
        .dropDestination(for: MacSongDrag.self) { items, _ in
            guard playlists.canEdit else { return false }
            playlists.add(items.map(\.song), to: playlist)
            return true
        }
        .contextMenu { MacPlaylistMenu(playlist: playlist) }
    }
}

/// The context menu for a playlist, in the sidebar and on Home.
struct MacPlaylistMenu: View {
    let playlist: Playlist

    @Environment(MacPlayback.self) private var playback
    @Environment(MacPlaylists.self) private var playlists

    var body: some View {
        Button("Play", systemImage: "play") { playback.playPlaylist(id: playlist.id) }
        Button("Shuffle", systemImage: "shuffle") { playback.playPlaylist(id: playlist.id, shuffled: true) }
        Divider()
        Button("Download", systemImage: "arrow.down.circle") { playback.downloadPlaylist(id: playlist.id) }
            .disabled(!playlists.canEdit)
        Divider()
        Button("Rename…") { playlists.renaming = playlist }
            .disabled(!playlists.canEdit)
        Button("Delete Playlist…", role: .destructive) { playlists.deleting = playlist }
            .disabled(!playlists.canEdit)
    }
}
