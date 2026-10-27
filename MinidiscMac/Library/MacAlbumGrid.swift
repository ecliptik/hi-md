import SwiftSonic
import SwiftUI

/// Album covers in a grid that fills the window's width. Put it inside a ScrollView.
struct MacAlbumGrid: View {
    let albums: [AlbumID3]
    var showsArtist = true

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(albums) { album in
                MacAlbumTile(album: album, showsArtist: showsArtist)
            }
        }
    }
}

/// One album: its cover, name and artist. Click opens it; the play button on hover plays it.
struct MacAlbumTile: View {
    let album: AlbumID3
    var showsArtist = true

    @Environment(MacPlayback.self) private var playback
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: MacDestination.album(id: album.id)) {
            VStack(alignment: .leading, spacing: 4) {
                CoverArtView(id: album.coverArt ?? album.id, size: 440, cornerRadius: 6, placeholderSystemImage: "square.stack")
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .overlay(alignment: .bottomLeading) {
                        if isHovering {
                            playButton
                                .padding(8)
                                .transition(.opacity)
                        }
                    }
                Text(album.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if showsArtist, let artist = album.artist {
                    Text(artist)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let year = album.year {
                    Text(String(year))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .contextMenu {
            MacAlbumMenu(albumID: album.id, albumName: album.name, artistID: album.artistId, artistName: album.artist)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the album")
    }

    private var playButton: some View {
        Button {
            playback.playAlbum(id: album.id)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play")
    }
}

/// The context menu for an album, wherever it appears.
struct MacAlbumMenu: View {
    let albumID: String
    /// Names the Instant Mix it offers; without it the menu has none.
    var albumName: String?
    var artistID: String?
    var artistName: String?
    /// Runs before Go to Artist, so a window other than the main one (the MiniPlayer) can bring
    /// the main window forward first.
    var beforeNavigating: (() -> Void)? = nil

    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator

    var body: some View {
        Button("Play", systemImage: "play") { playback.playAlbum(id: albumID) }
        Button("Shuffle", systemImage: "shuffle") { playback.playAlbum(id: albumID, action: .shuffle) }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            playback.playAlbum(id: albumID, action: .playNext)
        }
        Button("Add to Queue", systemImage: "text.append") { playback.playAlbum(id: albumID, action: .addToQueue) }
        if let albumName {
            Button("Instant Mix", systemImage: instantMixSymbol) { playback.playInstantMix(albumID: albumID, name: albumName) }
                .disabled(!playback.container.serverState.isOnline)
        }

        Divider()

        MacFavoriteMenuItem(itemType: .album, itemID: albumID)
        Button("Download", systemImage: "arrow.down.circle") { playback.downloadAlbum(id: albumID) }
            .disabled(!playback.container.serverState.isOnline)

        if let artistID {
            Divider()
            Button("Go to Artist", systemImage: "music.microphone") {
                beforeNavigating?()
                navigator.show(.artist(id: artistID, name: artistName ?? ""))
            }
        }
    }
}
