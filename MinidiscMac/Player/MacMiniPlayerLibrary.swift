import SwiftSonic
import SwiftUI

/// The MiniPlayer's Library pane, for picking music without the main window: Artists,
/// Playlists and Favorites, drilling down from an artist to their albums and an album's songs,
/// with Back to return. The search field narrows the list on screen (on the first page it
/// searches the whole library). Clicking a song plays the list from it; clicking an artist, album
/// or playlist opens it, and its play button plays it. Right-click has the usual menus.
///
/// A lazy stack rather than a List, as in the other panes: a List taken down while the window is
/// being resized crashes (see MiniPlayerQueueList).
struct MacMiniPlayerLibrary: View {
    @Bindable var model: LibraryBrowserModel
    /// The space at the rows' sides: the tall layout's inset, none beside the wide one's artwork.
    var rowInset: Double
    /// Brings the main window forward before a menu goes to a page or shows a sheet there.
    var beforeNavigating: () -> Void

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, rowInset)
                .padding(.top, 8)
            searchField
                .padding(.horizontal, rowInset)
                .padding(.vertical, 6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Header

    /// Back, the list's name, and Play and Shuffle for an artist, album, playlist or Favorites.
    private var header: some View {
        HStack(spacing: 4) {
            if model.canGoBack {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { model.goBack() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .accessibilityValue(Text(verbatim: model.previousLocation.map(title(of:)) ?? ""))
                .help("Back")
            }
            Text(verbatim: title(of: model.location))
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if canPlayList {
                headerButton("Play", systemImage: "play.fill") { playList(shuffled: false) }
                headerButton("Shuffle", systemImage: "shuffle") { playList(shuffled: true) }
            }
        }
        .frame(height: 24)
    }

    private func headerButton(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }

    private func title(of location: LibraryBrowserLocation) -> String {
        switch location {
        case .home: String(localized: "Library")
        case .artists: String(localized: "Artists")
        case .playlists: String(localized: "Playlists")
        case .favorites: String(localized: "Favorites")
        case .search: String(localized: "Search")
        case .artist(_, let name), .album(_, let name), .playlist(_, let name): name
        }
    }

    private var canPlayList: Bool {
        switch model.location {
        case .artist, .album, .playlist: true
        case .favorites: model.rows.contains { $0.song != nil }
        default: false
        }
    }

    private func playList(shuffled: Bool) {
        let action: MacPlayback.CollectionAction = shuffled ? .shuffle : .play
        switch model.location {
        case .artist(let id, _): playback.playArtist(id: id, action: action)
        case .album(let id, _): playback.playAlbum(id: id, action: action)
        case .playlist(let id, _): playback.playPlaylist(id: id, shuffled: shuffled)
        default:
            let songs = model.rows.compactMap(\.song)
            shuffled ? playback.shuffle(songs) : playback.play(songs)
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                .accessibilityHidden(true)
            TextField("Search", text: $model.query, prompt: Text("Search"))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(submitSearch)
                .onKeyPress(.escape) {
                    guard !model.query.isEmpty else { return .ignored }
                    model.query = ""
                    return .handled
                }
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
                .help("Clear")
            }
        }
        .font(.callout)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Return opens the first row that opens, or plays the first song.
    private func submitSearch() {
        guard let first = model.rows.first else { return }
        activate(first)
    }

    // MARK: Rows

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading where model.rows.isEmpty:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 8) {
                MiniPlayerEmptyTab(title: "Unable to Load", systemImage: "exclamationmark.triangle")
                    .frame(maxHeight: 60)
                Text(verbatim: message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                Button("Retry", action: model.reload)
                    .controlSize(.small)
            }
            .padding(.horizontal, rowInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if model.hasNoMatches {
                MiniPlayerEmptyTab(title: "No Results", systemImage: "magnifyingglass")
            } else if model.rows.isEmpty {
                emptyList
            } else {
                list
            }
        }
    }

    @ViewBuilder private var emptyList: some View {
        switch model.location {
        case .artists: MiniPlayerEmptyTab(title: "No Artists", systemImage: "music.microphone")
        case .playlists: MiniPlayerEmptyTab(title: "No Playlists", systemImage: "music.note.list")
        case .favorites: MiniPlayerEmptyTab(title: "No Favorites", systemImage: "heart")
        default: MiniPlayerEmptyTab(title: "No Results", systemImage: "magnifyingglass")
        }
    }

    private var list: some View {
        let rows = model.rows
        let currentID = playback.state.currentTrack?.id
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    if let group = item.group, index == 0 || rows[index - 1].group != group {
                        MiniPlayerListHeading(title: heading(group))
                    }
                    MiniPlayerLibraryRow(item: item, page: model.location, isCurrent: item.song?.id == currentID,
                                         activate: { activate(item) }, play: playAction(for: item),
                                         beforeNavigating: beforeNavigating)
                }
            }
            .padding(.horizontal, rowInset)
            .padding(.bottom, 8)
        }
        // A new list starts at its top.
        .id(model.shownPage.id)
    }

    private func heading(_ group: LibraryBrowserItem.Group) -> LocalizedStringKey {
        switch group {
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        }
    }

    /// A song plays the list from it; anything else opens.
    private func activate(_ item: LibraryBrowserItem) {
        if item.song != nil {
            guard let (songs, index) = model.songsToPlay(startingAt: item) else { return }
            playback.play(songs, from: index, context: playbackContext)
        } else {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { model.open(item) }
        }
    }

    /// "Playing from" for an album's or a playlist's songs.
    private var playbackContext: PlaybackContext? {
        switch model.location {
        case .album(let id, let name): .album(id: id, name: name, coverArtId: id)
        case .playlist(let id, let name): .forPlaylist(id: id, name: name, coverArtId: nil)
        default: nil
        }
    }

    /// The row's play button: an artist, album or playlist plays whole.
    private func playAction(for item: LibraryBrowserItem) -> (() -> Void)? {
        switch item.kind {
        case .artist(let id, _): { playback.playArtist(id: id) }
        case .album(let id, _, _, _): { playback.playAlbum(id: id) }
        case .playlist(let playlist): { playback.playPlaylist(id: playlist.id) }
        case .list, .song: nil
        }
    }
}

/// One row of the Library pane, with its menu and, on hover, a play button for what it opens.
private struct MiniPlayerLibraryRow: View {
    let item: LibraryBrowserItem
    /// The list the row is in, so an artist's albums don't repeat the artist.
    let page: LibraryBrowserLocation
    let isCurrent: Bool
    let activate: () -> Void
    let play: (() -> Void)?
    let beforeNavigating: () -> Void

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: activate) {
                if let song = item.song {
                    MiniPlayerSongRow(song: song, isCurrent: isCurrent) {
                        MiniPlayerDuration(seconds: song.duration)
                    }
                } else {
                    destinationLabel
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(item.song == nil ? Text(verbatim: "") : Text("Play"))
            if let play {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.minidiscAccentText)
                        .frame(width: 22, height: 22)
                        .background(Color.minidiscAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering || voiceOverEnabled ? 1 : 0)
                .allowsHitTesting(isHovering || voiceOverEnabled)
                .accessibilityLabel("Play")
                .help("Play")
            }
        }
        .onHover { isHovering = $0 }
        .contextMenu { menu }
    }

    private var destinationLabel: some View {
        HStack(spacing: 10) {
            artwork
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.name)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle {
                    subtitle
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var artwork: some View {
        switch item.kind {
        case .list(let location):
            Image(systemName: Self.symbol(for: location))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.minidiscAccent)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .artist(let id, _):
            CoverArtView(id: item.coverArtID ?? id, size: 64, cornerRadius: 16, placeholderSystemImage: "music.microphone")
                .clipShape(Circle())
        case .playlist(let playlist):
            CoverArtView(id: item.coverArtID ?? playlist.id, size: 64, cornerRadius: 3,
                         placeholderSystemImage: "music.note.list")
        default:
            CoverArtView(id: item.coverArtID ?? item.id, size: 64, cornerRadius: 3)
        }
    }

    private static func symbol(for location: LibraryBrowserLocation) -> String {
        switch location {
        case .artists: "music.microphone"
        case .playlists: "music.note.list"
        case .favorites: "heart"
        default: "music.note"
        }
    }

    private var subtitle: Text? {
        switch item.kind {
        case .artist(_, let albumCount?):
            return Text("\(albumCount) albums")
        case .album(_, let artist, _, let year):
            var parts: [String] = []
            if case .artist = page {} else if let artist, !artist.isEmpty { parts.append(artist) }
            if let year, year > 0 { parts.append(String(year)) }
            return parts.isEmpty ? nil : Text(verbatim: parts.joined(separator: " · "))
        case .playlist(let playlist):
            return Text("\(playlist.songCount) songs")
        default:
            return nil
        }
    }

    @ViewBuilder private var menu: some View {
        switch item.kind {
        case .song(let song):
            if !song.isLocalFile {
                FavoriteMatches(.song, id: song.id) { toggle in
                    MacSongMenu(songs: [song], isFavorite: toggle.isFavorite, beforeNavigating: beforeNavigating)
                }
            } else {
                MacSongMenu(songs: [song], beforeNavigating: beforeNavigating)
            }
        case .album(let id, let artist, let artistID, _):
            MacAlbumMenu(albumID: id, albumName: item.name, artistID: artistID, artistName: artist,
                         beforeNavigating: beforeNavigating)
        case .artist(let id, _):
            MacArtistMenu(artistID: id)
        case .playlist(let playlist):
            MacPlaylistMenu(playlist: playlist, beforeShowingSheet: beforeNavigating)
        case .list:
            EmptyView()
        }
    }
}
