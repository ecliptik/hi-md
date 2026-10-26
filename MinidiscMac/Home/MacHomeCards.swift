import SwiftData
import SwiftSonic
import SwiftUI

/// One playlist: its cover, name and when it changed. Click opens it; the play button on hover
/// plays it; the context menu is the sidebar's.
struct MacPlaylistTile: View {
    let playlist: Playlist
    var side: CGFloat = MacShelfMetrics.playlistSide

    @Environment(MacPlayback.self) private var playback
    @Environment(\.appContainer) private var container
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: MacDestination.playlist(id: playlist.id)) {
            VStack(alignment: .leading, spacing: 4) {
                PlaylistCoverThumbnail(playlistId: playlist.id, serverId: container?.serverState.activeServer?.id,
                                       coverArtId: playlist.coverArt ?? playlist.id, title: playlist.name, size: side)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .overlay(alignment: .bottomLeading) {
                        if isHovering {
                            MacHoverPlayButton { playback.playPlaylist(id: playlist.id) }
                                .padding(8)
                                .transition(.opacity)
                        }
                    }
                Text(playlist.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macCardHover($isHovering)
        .contextMenu { MacPlaylistMenu(playlist: playlist) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the playlist")
    }

    private var subtitle: String {
        if let changed = playlist.changed {
            return String(localized: "Updated \(changed.formatted(.relative(presentation: .named)))")
        }
        return String(localized: "\(playlist.songCount) tracks")
    }
}

/// Songs in a sideways shelf of short columns, like the Music app's Top Songs. A click or
/// Return plays from that song through the whole list; the context menu is every song list's.
struct MacSongShelf: View {
    let title: String
    let songs: [DisplayableSong]
    var onOpen: (() -> Void)? = nil

    private let rows = Array(repeating: GridItem(.fixed(MacSongShelfRow.height), spacing: 2), count: 4)

    var body: some View {
        let shown = Array(songs.prefix(MacShelfMetrics.previewLimit))
        MacShelf(title: title, onOpen: onOpen) {
            LazyHGrid(rows: Array(rows.prefix(min(rows.count, max(shown.count, 1)))), alignment: .top,
                      spacing: MacShelfMetrics.cardSpacing) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, song in
                    MacSongShelfRow(song: song, queue: songs, index: index)
                }
            }
        }
    }
}

struct MacSongShelfRow: View {
    static let height: CGFloat = 52

    let song: DisplayableSong
    /// The list the song is in, played from `index`.
    let queue: [DisplayableSong]
    let index: Int

    @Environment(MacPlayback.self) private var playback
    @Environment(\.minidiscPlayingAccent) private var playingAccent
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    private var isCurrent: Bool { playback.state.currentTrack?.id == song.id }

    var body: some View {
        FavoriteMatches(.song, id: song.id) { toggle in
            HStack(spacing: 10) {
                CoverArtView(id: song.coverArtId ?? song.id, size: 80, cornerRadius: 4)
                    .frame(width: 40, height: 40)
                    .overlay {
                        if isHovering {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityHidden(true)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .foregroundStyle(isCurrent ? playingAccent : .primary)
                        .lineLimit(1)
                    Text(song.artist ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Button {
                    playback.setFavorite(toggle.toggled, songs: [song])
                } label: {
                    Image(systemName: toggle.systemImage)
                        .foregroundStyle(toggle.isFavorite ? playingAccent : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .disabled(song.isLocalFile || !playback.container.serverState.isOnline)
                .help(Text(toggle.actionTitle))
                .accessibilityLabel(Text(toggle.actionTitle))
            }
            .padding(.horizontal, 6)
            .frame(width: 300, height: Self.height)
            .background(background, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            // A click plays, as in Music's song shelves, and selects the row for the keyboard.
            .onTapGesture {
                isFocused = true
                play()
            }
            .onKeyPress(.return) {
                play()
                return .handled
            }
            .draggable(MacSongDrag(song: song))
            .contextMenu { MacSongMenu(songs: [song], isFavorite: toggle.isFavorite) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { play() }
            .accessibilityAction(named: Text(toggle.actionTitle)) {
                playback.setFavorite(toggle.toggled, songs: [song])
            }
            .accessibilityHint("Plays the song")
        }
    }

    private var background: Color {
        if isFocused { return Color.minidiscAccent.opacity(0.22) }
        return isHovering ? Color.primary.opacity(0.06) : .clear
    }

    private func play() {
        playback.play(queue, from: index)
    }
}
