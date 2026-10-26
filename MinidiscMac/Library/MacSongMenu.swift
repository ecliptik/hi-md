import SwiftSonic
import SwiftUI

/// The context menu for one or more songs, used by every song table.
struct MacSongMenu: View {
    let songs: [DisplayableSong]
    /// The selection's favourite state, so the menu offers the opposite.
    var isFavorite = false
    /// A playlist's Remove from Playlist, or nil elsewhere.
    var onRemove: (() -> Void)? = nil
    /// Runs before Go to Album or Go to Artist, so a window other than the main one (the
    /// MiniPlayer) can bring the main window forward first.
    var beforeNavigating: (() -> Void)? = nil

    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator

    private var serverSongs: [DisplayableSong] { songs.filter { !$0.isLocalFile } }

    var body: some View {
        Button("Play", systemImage: "play") { playback.play(songs) }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { playback.playNext(songs) }
        Button("Add to Queue", systemImage: "text.append") { playback.addToQueue(songs) }
        if songs.count == 1, let song = songs.first, !song.isLocalFile {
            Button("Instant Mix", systemImage: instantMixSymbol) { playback.playInstantMix(from: song) }
                .disabled(!playback.container.serverState.isOnline)
        }

        Divider()

        MacAddToPlaylistMenu(songs: songs)

        Button(isFavorite ? "Remove from Favorites" : "Add to Favorites",
               systemImage: isFavorite ? "heart.slash" : "heart") {
            playback.setFavorite(!isFavorite, songs: songs)
        }
        .disabled(serverSongs.isEmpty || !playback.container.serverState.isOnline)

        Button("Download", systemImage: "arrow.down.circle") { playback.download(songs) }
            .disabled(serverSongs.allSatisfy(\.isDownloaded) || !playback.container.serverState.isOnline)

        if songs.count == 1, let song = songs.first {
            Divider()
            Button("Go to Album", systemImage: "square.stack") {
                beforeNavigating?()
                navigator.showAlbum(of: song, highlighting: true)
            }
                .disabled(song.albumId == nil)
            Button("Go to Artist", systemImage: "music.microphone") {
                beforeNavigating?()
                navigator.showArtist(of: song)
            }
                .disabled(song.artistId == nil)
        }

        if let onRemove {
            Divider()
            Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive, action: onRemove)
        }
    }
}

/// Add to Playlist, as a submenu of the user's playlists with New Playlist… at the top.
struct MacAddToPlaylistMenu: View {
    let songs: [DisplayableSong]

    @Environment(MacPlaylists.self) private var playlists

    var body: some View {
        Menu {
            Button("New Playlist…") { playlists.requestNewPlaylist(with: songs) }
            if !playlists.playlists.isEmpty {
                Divider()
                ForEach(playlists.playlists) { playlist in
                    Button(playlist.name) { playlists.add(songs, to: playlist) }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "music.note.list")
        }
        .disabled(!playlists.canEdit || songs.allSatisfy(\.isLocalFile))
    }
}
