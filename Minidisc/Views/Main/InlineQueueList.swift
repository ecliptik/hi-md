import SwiftUI
import SwiftData
import OSLog
import UniformTypeIdentifiers

private struct QueueRow: View {
    let song: DisplayableSong
    let isCurrent: Bool
    let onRemove: (() -> Void)?
    var contentColor: Color = .primary
    var secondaryContentColor: Color = .secondary
    var loadArtwork: Bool = true
    var showsReorderHint: Bool = false

    @Environment(\.appContainer) private var container
    @Environment(PlaylistAddition.self) private var playlistAddition
    @Environment(\.minidiscPlayingAccent) private var playingAccent
    @Query private var favoriteMatches: [FavoriteRecord]

    init(song: DisplayableSong, isCurrent: Bool, onRemove: (() -> Void)? = nil,
         contentColor: Color = .primary, secondaryContentColor: Color = .secondary, loadArtwork: Bool = true,
         showsReorderHint: Bool = false) {
        self.song = song
        self.isCurrent = isCurrent
        self.onRemove = onRemove
        self.contentColor = contentColor
        self.secondaryContentColor = secondaryContentColor
        self.loadArtwork = loadArtwork
        self.showsReorderHint = showsReorderHint
        let cid = "song:\(song.id)"
        _favoriteMatches = Query(filter: #Predicate<FavoriteRecord> { $0.id == cid })
    }

    private var isOnline: Bool { container?.serverState.isOnline == true }
    private var isPlaying: Bool { container?.playerState.playbackState == .playing }
    private var isFavorite: Bool { !favoriteMatches.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            titleAndArtwork
                .contentShape(Rectangle())
                .contextMenu { queueMenu }

            if isCurrent {
                NowPlayingBarsIndicator(isPlaying: isPlaying)
            } else if showsReorderHint {
                // Keep the handle outside the context menu's long-press region.
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(secondaryContentColor.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Reorder")
                    .accessibilityIdentifier("queue.reorder.\(song.id)")
            }
        }
        .padding(.vertical, MinidiscSpacing.xs)
        .modifier(SongQuickActions(song: song, onAddToPlaylist: playlistAddition.present, onRemove: onRemove))
    }

    private var titleAndArtwork: some View {
        HStack(spacing: MinidiscSpacing.m) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 88, loadingEnabled: loadArtwork)
                .frame(width: 44, height: 44)
                .minidiscCoverStyle(cornerRadius: MinidiscCornerRadius.xs)

            VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
                Text(song.title)
                    .font(.minidiscCellTitle)
                    .foregroundStyle(isCurrent ? playingAccent : contentColor)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.minidiscCaption)
                        .foregroundStyle(secondaryContentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var queueMenu: some View {
        Group {
            Button {
                Task {
                    do {
                        try await container?.playerService.play(tracks: [song], startIndex: 0)
                    } catch {
                        Logger.player.error("[PLAYBACK] play failed: \(error, privacy: .public)")
                        if !UserFacingError.isCancellation(error) {
                            container?.toastService.showError(UserFacingError.from(error).displayMessage)
                        }
                    }
                }
            } label: {
                Label("Play", systemImage: "play.fill")
            }

            Button {
                Task { await container?.playerService.playNext(song) }
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                Task { await container?.playerService.addToQueue(song) }
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }

            Divider()

            Button {
                playlistAddition.present(song)
            } label: {
                Label("Add to Playlist...", systemImage: "music.note.list")
            }
            .disabled(!isOnline || song.isLocalFile)

            Divider()

            Button {
                let fav = isFavorite
                Task {
                    if fav {
                        await container?.toastService.perform { try await container?.favoritesService.unstar(itemType: .song, itemId: song.id) }
                    } else {
                        await container?.toastService.perform { try await container?.favoritesService.star(itemType: .song, itemId: song.id) }
                    }
                }
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "heart.slash" : "heart"
                )
            }
            .disabled(!isOnline || song.isLocalFile)

            if let onRemove {
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Queue", systemImage: "minus.circle")
                }
            }
        }
        .tint(.primary)
    }
}

/// The next songs remain directly below the playback modes. Native drag and swipe can coexist
/// on iOS 27; the earlier system keeps the existing always-visible reorder handles.
struct InlineQueueList: View {
    let playerState: PlayerState
    var contentColor: Color = .primary
    var secondaryContentColor: Color = .secondary
    var loadArtwork: Bool = true

    /// Rows shown before "Show More". A queue from the Songs tab can hold 200,000 tracks; listing
    /// them all made every skip diff that many rows on the MainActor the engine's transitions use.
    static let pageSize = 200

    @State private var rowLimit = Self.pageSize
    /// Occurrence counts change only with the queue, not on a skip.
    @State private var occurrences = DerivedValueCache<UInt64, [Int]>()
    @State private var rows = DerivedValueCache<RowsKey, [QueueUpcomingRow]>()

    private struct RowsKey: Equatable {
        let generation: UInt64
        let revision: UInt64
        let currentIndex: Int
        let currentTrackID: String?
        let limit: Int
    }

    var body: some View {
        let entries = upcomingRows()
        if entries.isEmpty {
            EmptyStateView(systemImage: "list.bullet", title: "Nothing up next",
                           subtitle: "Tracks you add to the queue appear here.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let hiddenCount = playerState.queue.count - (entries[entries.count - 1].index + 1)
            ReorderableQueueList(entries: entries, queueCount: playerState.queue.count, hiddenCount: hiddenCount,
                                 contentColor: contentColor, secondaryContentColor: secondaryContentColor,
                                 loadArtwork: loadArtwork, onShowMore: { rowLimit += Self.pageSize })
        }
    }

    private func upcomingRows() -> [QueueUpcomingRow] {
        let queue = playerState.queue
        let key = RowsKey(generation: playerState.queueGeneration, revision: playerState.queueRevision,
                          currentIndex: playerState.currentIndex, currentTrackID: playerState.currentTrack?.id,
                          limit: rowLimit)
        return rows.value(for: key) {
            let counts = occurrences.value(for: key.revision) { QueueUpcomingRow.occurrences(in: queue) }
            return QueueUpcomingRow.upcoming(in: playerState, occurrences: counts, limit: rowLimit)
        }
    }
}

private struct QueueEntryRow: View {
    let entry: QueueUpcomingRow
    let contentColor: Color
    let secondaryContentColor: Color
    let loadArtwork: Bool
    var showsReorderHint = false
    @Environment(\.appContainer) private var container

    var body: some View {
        QueueRow(song: entry.song, isCurrent: false, onRemove: remove,
                 contentColor: contentColor, secondaryContentColor: secondaryContentColor,
                 loadArtwork: loadArtwork, showsReorderHint: showsReorderHint)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .contentShape(Rectangle())
            .accessibilityIdentifier("queue.track.\(entry.song.id).\(entry.id.occurrence)")
            .onTapGesture {
                HapticFeedback.medium.trigger()
                guard let selection = container.flatMap({ entry.selection(in: $0.playerState) }) else { return }
                Task {
                    await container?.toastService.perform {
                        _ = try await container?.playerService.selectQueueTrack(selection)
                    }
                }
            }
    }

    private func remove() {
        guard let selection = container.flatMap({ entry.selection(in: $0.playerState) }) else { return }
        Task {
            guard let removal = await container?.playerService.removeQueueTrack(selection) else { return }
            HapticFeedback.light.trigger()
            container?.toastService.show(String(localized: "Removed from queue"), subtitle: removal.song.title,
                                         style: .success, duration: 6, coverArtId: removal.song.coverArtId,
                                         action: .undoQueueRemoval(removal))
        }
    }
}

private struct ReorderableQueueList: View {
    let entries: [QueueUpcomingRow]
    let queueCount: Int
    /// Upcoming songs after the last row shown.
    let hiddenCount: Int
    let contentColor: Color
    let secondaryContentColor: Color
    let loadArtwork: Bool
    let onShowMore: () -> Void
    @Environment(\.appContainer) private var container

    var body: some View {
        List {
            ForEach(entries) { entry in
                QueueEntryRow(entry: entry, contentColor: contentColor, secondaryContentColor: secondaryContentColor,
                              loadArtwork: loadArtwork, showsReorderHint: true)
            }
            .reorderable()
            // Apply row traits outside the reorderable wrapper so List receives them.
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            if hiddenCount > 0 {
                Button("Show More", action: onShowMore)
                    .font(.minidiscBody)
                    .foregroundStyle(secondaryContentColor)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("queue.showMore")
            }
        }
        .reorderContainer(for: QueueUpcomingRow.self) { difference in
            guard difference.sources.count == 1,
                  let source = difference.sources.first,
                  let entry = entries.first(where: { $0.id == source }),
                  let selection = container.flatMap({ entry.selection(in: $0.playerState) }) else { return }
            let destination: Int
            switch difference.destination.position {
            case .before(let id):
                guard let target = entries.first(where: { $0.id == id }) else { return }
                destination = target.index
            case .end:
                // Past the last row shown, which is the end of the queue only when nothing is hidden.
                destination = hiddenCount > 0 ? entries[entries.count - 1].index + 1 : queueCount
            }
            Logger.player.debug("Queue drag requested: \(selection.destinationIndex) → \(destination)")
            HapticFeedback.light.trigger()
            Task { await container?.playerService.moveQueueTrack(selection, toIndex: destination) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
