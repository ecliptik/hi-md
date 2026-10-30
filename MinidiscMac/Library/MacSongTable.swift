import AppKit
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
                        .foregroundStyle(style == .album ? .secondary : .primary)
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
        // An album lays out like the Music app's: roomy rows divided by hairlines, no stripes
        // and no column headers. Other lists keep the denser sortable table of its Songs view.
        .tableColumnHeaders(style == .album ? .hidden : .automatic)
        .alternatingRowBackgrounds(style == .album ? .disabled : .enabled)
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
        // The tallest cell sets the row's height.
        .padding(.vertical, style == .album ? Self.albumRowPadding : 0)
        .background { MacTableRowStyler(separators: style == .album) }
    }

    /// Makes an album's rows about 36 points tall, as in Music.
    private static let albumRowPadding: CGFloat = 9

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

/// Reaches the NSTableView behind a SwiftUI Table, which on the Mac has no row separators or
/// hover highlight, from inside one of its cells. Where no table is found the rows go without.
private struct MacTableRowStyler: NSViewRepresentable {
    /// Hairlines between the rows, as in a Music album.
    var separators: Bool

    func makeNSView(context: Context) -> NSView { Hook(separators: separators) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Hook: NSView {
        private let separators: Bool

        init(separators: Bool) {
            self.separators = separators
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var ancestor = superview
            while let view = ancestor, !(view is NSTableView) { ancestor = view.superview }
            guard let table = ancestor as? NSTableView else { return }
            if separators, !table.gridStyleMask.contains(.solidHorizontalGridLineMask) {
                table.gridStyleMask.insert(.solidHorizontalGridLineMask)
                table.gridColor = .separatorColor
            }
            MacTableHoverHighlight.install(in: table)
        }
    }
}

/// Lights up the row under the pointer, as Music does. It covers the table without taking clicks,
/// and draws a layer above the rows, which AppKit adds and reorders as the table scrolls.
private final class MacTableHoverHighlight: NSView {
    private weak var table: NSTableView?
    private let highlight = CALayer()
    private var hoveredRow = -1

    static func install(in table: NSTableView) {
        guard !table.subviews.contains(where: { $0 is MacTableHoverHighlight }) else { return }
        table.addSubview(MacTableHoverHighlight(table: table), positioned: .below, relativeTo: nil)
    }

    private init(table: NSTableView) {
        self.table = table
        super.init(frame: table.bounds)
        autoresizingMask = [.width, .height]
        table.wantsLayer = true
        highlight.cornerRadius = 6
        highlight.zPosition = 1
        highlight.isHidden = true
        table.layer?.addSublayer(highlight)
        updateColor()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self))
        if let clip = table.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(contentScrolled),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The table's own coordinates, so a point here is a point in the table.
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { hover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hover(at: nil) }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    /// Rows slide under a still pointer while the list scrolls.
    @objc private func contentScrolled(_ notification: Notification) {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        hover(at: visibleRect.contains(point) ? point : nil)
    }

    private func hover(at point: NSPoint?) {
        guard let table else { return }
        let row = point.map { table.row(at: $0) } ?? -1
        guard row != hoveredRow else { return }
        hoveredRow = row
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if row >= 0 {
            highlight.frame = table.rowView(atRow: row, makeIfNecessary: false)?.frame ?? table.rect(ofRow: row)
            highlight.isHidden = false
        } else {
            highlight.isHidden = true
        }
        CATransaction.commit()
    }

    private func updateColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            highlight.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        }
    }
}
