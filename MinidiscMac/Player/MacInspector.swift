import SwiftUI

/// The panel on the right of the window: the playing song's lyrics, or the queue.
struct MacInspector: View {
    let container: AppContainer

    @Environment(MacNavigator.self) private var navigator
    @State private var lyrics = MacLyricsSession()

    var body: some View {
        @Bindable var navigator = navigator
        let pane = navigator.inspector ?? .queue
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Show", selection: Binding(get: { navigator.inspector ?? .queue }, set: { navigator.inspector = $0 })) {
                    Text("Lyrics").tag(MacInspectorPane.lyrics)
                    Text("Playing Next").tag(MacInspectorPane.queue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if pane == .lyrics, lyrics.hasLyrics, let viewModel = lyrics.viewModel {
                    lyricsButtons(viewModel)
                }
            }
            .padding(12)
            Divider()
            switch pane {
            case .lyrics:
                MacLyricsPane(container: container, session: lyrics)
            case .queue:
                MacQueuePane()
            }
        }
        .background(.background)
    }

    /// Follow Lyrics, and Full Screen Lyrics, which opens Now Playing straight into the Mac's
    /// full-screen lyrics rather than the iPhone's karaoke sheet.
    private func lyricsButtons(_ viewModel: LyricsViewModel) -> some View {
        HStack(spacing: 2) {
            Toggle(isOn: Binding(get: { viewModel.autoScrollEnabled }, set: { viewModel.autoScrollEnabled = $0 })) {
                Label("Follow Lyrics", systemImage: "arrow.up.arrow.down")
            }
            .toggleStyle(.button)
            .help("Follow Lyrics")
            Button {
                navigator.showNowPlaying(fullScreenLyrics: true)
            } label: {
                Label("Full Screen Lyrics", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Full Screen Lyrics")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}

/// Time-synced lyrics for the playing song, through the shared lyrics view and view model. The
/// lyrics stay loaded while the song plays, so switching panes doesn't fetch them again.
struct MacLyricsPane: View {
    let container: AppContainer
    /// Shares the loaded lyrics with controls outside the pane (the Now Playing view's follow
    /// and full-screen buttons, the MiniPlayer's menu).
    var session: MacLyricsSession? = nil
    /// The Mac's full-screen lyrics: huge centred lines instead of the player's column.
    var isFullScreen = false
    /// Takes up the session's lyrics when they're for the same song, so a pane that comes and
    /// goes (the MiniPlayer's, as its layout changes) doesn't load them again. Only for a session
    /// that one pane shows at a time.
    var adoptsSessionLyrics = false

    @State private var viewModel: LyricsViewModel?

    private var trackID: String? { container.playerState.currentTrack?.id }

    var body: some View {
        let playerState = container.playerState
        Group {
            if let track = playerState.currentTrack, !track.isLocalFile, !playerState.isLiveStream {
                if let viewModel {
                    if isFullScreen {
                        MacFullScreenLyricsLines(viewModel: viewModel)
                            .id(track.id)
                    } else {
                        LyricsView(viewModel: viewModel)
                            .id(track.id)
                            .padding(.horizontal, 12)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContentUnavailableView("No Lyrics", systemImage: "quote.bubble",
                                       description: Text("Lyrics appear here for the song that's playing."))
            }
        }
        // The shared view's own full-screen button opens the iPhone's phone-sized karaoke sheet,
        // so on the Mac the views around the pane offer their own buttons instead.
        .transformEnvironment(\.lyricsTypography) { $0.showsHeaderButtons = false }
        .task(id: LyricsKey(trackID: trackID, source: container.lyricsSettings.source)) {
            await loadLyrics()
        }
        .onChange(of: viewModel.map(ObjectIdentifier.init), initial: true) {
            session?.viewModel = viewModel
        }
    }

    private struct LyricsKey: Equatable {
        let trackID: String?
        let source: LyricsSource
    }

    private func loadLyrics() async {
        let source = container.lyricsSettings.source
        guard let track = container.playerState.currentTrack, !track.isLocalFile,
              let serverID = container.serverState.activeServer?.id else {
            viewModel = nil
            return
        }
        if viewModel?.canBeReused(forTrackID: track.id, source: source) == true { return }
        if adoptsSessionLyrics, let shared = session?.viewModel,
           shared.canBeReused(forTrackID: track.id, source: source) {
            viewModel = shared
            return
        }
        let model = LyricsViewModel(track: track, serverId: serverID, source: source,
                                    lyricsService: container.lyricsService,
                                    playerService: container.playerService, playerState: container.playerState)
        viewModel = model
        await model.load()
    }
}

/// The lyrics a MacLyricsPane has loaded, for the controls around it.
@Observable
@MainActor
final class MacLyricsSession {
    var viewModel: LyricsViewModel?

    /// Lyrics to follow or show full screen, not a loading or empty state.
    var hasLyrics: Bool {
        if case .loaded = viewModel?.state { return true }
        return false
    }
}

/// The song playing now, then Up Next: drag to reorder, double-click to jump, Delete to remove.
struct MacQueuePane: View {
    /// The Now Playing views show the song beside the queue already, and their own backdrop
    /// behind the list.
    var isOnBackdrop = false

    @Environment(MacPlayback.self) private var playback
    @State private var selection: Set<MacQueueEntry.ID> = []

    var body: some View {
        let state = playback.state
        let entries = MacQueueEntry.upcoming(in: state)
        VStack(spacing: 0) {
            if !isOnBackdrop, let current = state.currentTrack {
                HStack(spacing: 10) {
                    CoverArtView(id: current.coverArtId ?? current.id, size: 96, cornerRadius: 4)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Now Playing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(current.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        if let artist = current.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                Divider()
            }
            HStack {
                Text("Playing Next")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    selection = []
                    playback.clearUpNext()
                }
                .buttonStyle(.borderless)
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if entries.isEmpty {
                ContentUnavailableView("Nothing up next", systemImage: "list.bullet",
                                       description: Text("Tracks you add to the queue appear here."))
            } else {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        MacQueueRow(song: entry.song, isOnBackdrop: isOnBackdrop)
                            .tag(entry.id)
                    }
                    .onMove { offsets, destination in
                        move(offsets, to: destination, in: entries, queueCount: state.queue.count)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(isOnBackdrop ? .hidden : .automatic)
                .contextMenu(forSelectionType: MacQueueEntry.ID.self) { ids in
                    let chosen = entries.filter { ids.contains($0.id) }
                    if !chosen.isEmpty {
                        Button("Remove from Queue", systemImage: "minus.circle") { remove(chosen) }
                    }
                } primaryAction: { ids in
                    guard let entry = entries.first(where: { ids.contains($0.id) }) else { return }
                    playback.jump(to: entry.selection)
                }
                .onDeleteCommand {
                    remove(entries.filter { selection.contains($0.id) })
                    selection = []
                }
            }
        }
    }

    private func remove(_ chosen: [MacQueueEntry]) {
        playback.removeFromQueue(chosen.map(\.selection))
    }

    /// List offsets count from the first song after the current one.
    private func move(_ offsets: IndexSet, to destination: Int, in entries: [MacQueueEntry], queueCount: Int) {
        guard offsets.count == 1, let source = offsets.first, entries.indices.contains(source) else { return }
        let target = destination < entries.count ? entries[destination].selection.destinationIndex : queueCount
        playback.moveInQueue(entries[source].selection, to: target)
    }
}

/// A song after the current one, with the request that jumps to, moves or removes it only if the
/// queue hasn't changed since the row was drawn.
struct MacQueueEntry: Identifiable {
    struct ID: Hashable {
        let generation: UInt64
        let songID: String
        let occurrence: Int
    }

    let id: ID
    let song: DisplayableSong
    let selection: QueueTrackSelection

    static func upcoming(in state: PlayerState) -> [MacQueueEntry] {
        var occurrences: [String: Int] = [:]
        return state.queue.enumerated().compactMap { index, song in
            let occurrence = occurrences[song.id, default: 0]
            occurrences[song.id] = occurrence + 1
            guard index > state.currentIndex,
                  let selection = QueueTrackSelection(playerState: state, destinationIndex: index,
                                                      destinationTrackID: song.id) else { return nil }
            return MacQueueEntry(id: ID(generation: state.queueGeneration, songID: song.id, occurrence: occurrence),
                                 song: song, selection: selection)
        }
    }
}

private struct MacQueueRow: View {
    let song: DisplayableSong
    var isOnBackdrop = false

    /// Over the artwork backdrop the system secondary falls under 4.5:1, so it uses the player's.
    private var secondary: AnyShapeStyle {
        isOnBackdrop ? AnyShapeStyle(Color.white.opacity(NowPlayingText.secondaryOpacity)) : AnyShapeStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 64, cornerRadius: 3)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(Duration.seconds(song.duration).formatted(.time(pattern: .minuteSecond)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(secondary)
        }
        .padding(.vertical, 2)
    }
}
