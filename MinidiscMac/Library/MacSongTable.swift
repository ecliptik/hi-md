import SwiftData
import SwiftUI

/// A sortable table of songs, like the Music app's song lists. Double-click or Return plays from
/// that song in the order shown; the context menu works on the selection; rows drag onto a
/// playlist in the sidebar.
struct MacSongTable: View {
    enum Style {
        /// An album: track numbers, no album or artwork column.
        case album
        /// A playlist: its order, which drags rearrange, and Remove from Playlist.
        case playlist
        /// Any other list of songs.
        case standard
    }

    /// Edits a playlist from its table. Positions are indexes into `songs`.
    struct PlaylistEditing {
        let playlistID: String
        let remove: (IndexSet) -> Void
        let move: (IndexSet, Int) -> Void
        let add: ([DisplayableSong]) -> Void
    }

    let songs: [DisplayableSong]
    var style: Style = .standard
    var editing: PlaylistEditing? = nil
    /// Selects this song when the table appears, as Go to Current Song does.
    var highlightedSongID: String? = nil
    /// The list's stored sort, which its toolbar's sort menu also sets; clicking a column header
    /// changes it. Without one the table sorts by its headers only while it's on screen.
    var sort: Binding<LibrarySortOrder<SongSortField>>? = nil

    @Environment(MacPlayback.self) private var playback
    @Environment(\.minidiscPlayingAccent) private var playingAccent
    @Query(filter: #Predicate<FavoriteRecord> { $0.itemType == "song" }) private var favoriteRecords: [FavoriteRecord]
    @State private var selection: Set<SongTableRow.ID> = []
    @State private var sortOrder: [SongTableComparator] = []

    /// The comparators in effect: the stored sort's, or the headers' clicked here.
    private var comparators: [SongTableComparator] {
        sort.map { [$0.wrappedValue.comparator] } ?? sortOrder
    }

    private var comparatorsBinding: Binding<[SongTableComparator]> {
        Binding {
            comparators
        } set: { newValue in
            if let sort {
                if let first = newValue.first { sort.wrappedValue = LibrarySortOrder(comparator: first) }
            } else {
                sortOrder = newValue
            }
        }
    }

    /// Whether the rows show in the list's own order.
    private var isListOrder: Bool {
        comparators.allSatisfy { $0.column == .position && $0.order == .forward }
    }

    private var rows: [SongTableRow] {
        let rows = SongTableRow.rows(songs)
        return isListOrder ? rows : rows.sorted(using: comparators)
    }

    private var favoriteIDs: Set<String> { Set(favoriteRecords.map(\.itemId)) }

    /// Albums by one artist leave the artist out; compilations show it.
    private var showsArtist: Bool {
        style != .album || Set(songs.compactMap(\.artist)).count > 1
    }

    var body: some View {
        let rows = rows
        let favorites = favoriteIDs
        Table(of: SongTableRow.self, selection: $selection, sortOrder: comparatorsBinding) {
            if style != .standard {
                TableColumn(Text(verbatim: "#"), sortUsing: SongTableComparator(column: .position)) { row in
                    numberCell(row)
                }
                .width(min: 28, ideal: 32, max: 44)
            }
            TableColumn("Title", sortUsing: SongTableComparator(column: .title)) { row in
                titleCell(row)
            }
            .width(min: 160, ideal: 280)
            if showsArtist {
                TableColumn("Artist", sortUsing: SongTableComparator(column: .artist)) { row in
                    Text(row.song.artist ?? "")
                }
                .width(min: 100, ideal: 180)
            }
            if style != .album {
                TableColumn("Album", sortUsing: SongTableComparator(column: .album)) { row in
                    Text(row.song.albumName ?? "")
                }
                .width(min: 100, ideal: 180)
            }
            TableColumn("Time", sortUsing: SongTableComparator(column: .duration)) { row in
                Text(Duration.seconds(row.song.duration).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 44, ideal: 52, max: 70)
            .alignment(.trailing)
            TableColumn(Text(Image(systemName: "heart"))) { row in
                favoriteCell(row, isFavorite: favorites.contains(row.song.id))
            }
            .width(min: 22, ideal: 26, max: 30)
            .alignment(.center)
        } rows: {
            if let editing {
                ForEach(rows) { row in
                    TableRow(row)
                        .draggable(MacSongDrag(song: row.song, playlistID: editing.playlistID, position: row.position))
                }
                .dropDestination(for: MacSongDrag.self) { index, items in
                    drop(items, at: index, into: editing, shownRows: rows)
                }
            } else {
                ForEach(rows) { row in
                    TableRow(row)
                        .draggable(MacSongDrag(song: row.song))
                }
            }
        }
        .contextMenu(forSelectionType: SongTableRow.ID.self) { ids in
            let chosen = songs(for: ids, in: rows)
            if !chosen.isEmpty {
                MacSongMenu(
                    songs: chosen,
                    isFavorite: chosen.allSatisfy { favorites.contains($0.id) },
                    onRemove: editing.map { editing in { editing.remove(IndexSet(ids)) } }
                )
            }
        } primaryAction: { ids in
            play(from: ids, in: rows)
        }
        .onDeleteCommand {
            guard let editing, !selection.isEmpty else { return }
            editing.remove(IndexSet(selection))
            selection = []
        }
        .onChange(of: songs.map(\.id)) {
            selection = []
            highlight()
        }
        .onAppear(perform: highlight)
        .onChange(of: highlightedSongID) { highlight() }
    }

    // MARK: - Cells

    @ViewBuilder
    private func numberCell(_ row: SongTableRow) -> some View {
        if isCurrent(row.song) {
            Image(systemName: playback.state.wantsPlayback ? "speaker.wave.2.fill" : "speaker.fill")
                .foregroundStyle(playingAccent)
                .accessibilityLabel("Now Playing")
        } else {
            let number = style == .album ? row.song.trackNumber : row.position + 1
            Text(number.map(String.init) ?? "")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func titleCell(_ row: SongTableRow) -> some View {
        HStack(spacing: 8) {
            if style != .album {
                CoverArtView(id: row.song.coverArtId ?? row.song.id, size: 48, cornerRadius: 3)
                    .frame(width: 24, height: 24)
            }
            Text(row.song.title)
                .foregroundStyle(isCurrent(row.song) ? playingAccent : .primary)
                .lineLimit(1)
            if row.song.isDownloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Downloaded")
            }
            if style == .standard, isCurrent(row.song) {
                Image(systemName: "speaker.wave.2.fill")
                    .imageScale(.small)
                    .foregroundStyle(playingAccent)
                    .accessibilityLabel("Now Playing")
            }
        }
    }

    private func favoriteCell(_ row: SongTableRow, isFavorite: Bool) -> some View {
        Button {
            playback.setFavorite(!isFavorite, songs: [row.song])
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? playingAccent : Color.secondary.opacity(0.5))
        }
        .buttonStyle(.borderless)
        .disabled(row.song.isLocalFile || !playback.container.serverState.isOnline)
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }

    // MARK: - Actions

    private func isCurrent(_ song: DisplayableSong) -> Bool {
        playback.state.currentTrack?.id == song.id
    }

    private func songs(for ids: Set<SongTableRow.ID>, in rows: [SongTableRow]) -> [DisplayableSong] {
        rows.filter { ids.contains($0.id) }.map(\.song)
    }

    /// Plays the list as shown, from the first chosen row.
    private func play(from ids: Set<SongTableRow.ID>, in rows: [SongTableRow]) {
        guard let start = rows.firstIndex(where: { ids.contains($0.id) }) else { return }
        playback.play(rows.map(\.song), from: start)
    }

    /// A drop from this playlist moves its rows; songs from anywhere else are added. Moving needs the
    /// playlist's own order on screen, so a sorted table only accepts new songs.
    private func drop(_ items: [MacSongDrag], at index: Int, into editing: PlaylistEditing, shownRows: [SongTableRow]) {
        let ownPositions = items.compactMap { $0.playlistID == editing.playlistID ? $0.position : nil }
        if ownPositions.count == items.count {
            guard isListOrder, !ownPositions.isEmpty else { return }
            editing.move(IndexSet(ownPositions), index)
            selection = []
        } else {
            editing.add(items.filter { $0.playlistID != editing.playlistID }.map(\.song))
        }
    }

    private func highlight() {
        guard let highlightedSongID, let row = SongTableRow.rows(songs).first(where: { $0.song.id == highlightedSongID }) else {
            return
        }
        selection = [row.id]
    }
}
