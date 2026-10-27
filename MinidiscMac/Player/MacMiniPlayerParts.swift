import AppKit
import AVKit
import SwiftSonic
import SwiftUI

// MARK: - Window

extension MacWindowHandle {
    /// A handle that only ever takes the MiniPlayer's own window, never a main window.
    static func miniPlayer() -> MacWindowHandle {
        let handle = MacWindowHandle()
        handle.adopts = { window in
            MiniPlayerWindowIdentity.mayAdopt(identifier: window.identifier?.rawValue,
                                              miniPlayerID: MacMiniPlayer.windowID,
                                              mainID: MacMenuBarPlayer.mainWindowID)
        }
        return handle
    }

    /// The window's limits in `layout`: a compact window keeps a 1:1 aspect ratio between its
    /// smallest and largest side, so dragging any edge scales the artwork; with a pane it resizes
    /// freely above the layout's minimum; a bar keeps its height and only changes its width.
    func applyMiniPlayerLimits(for layout: MiniPlayerLayout) {
        applyMiniPlayerLimits(minimum: layout.minimumSize, maximum: layout.maximumSize, keepsSquare: layout.keepsSquare)
    }

    /// The window's limits while it animates between two layouts: room for both, no aspect ratio.
    func applyMiniPlayerLimits(during change: MiniPlayerLayoutChange) {
        applyMiniPlayerLimits(minimum: change.minimumSize, maximum: change.maximumSize, keepsSquare: false)
    }

    private func applyMiniPlayerLimits(minimum: CGSize, maximum: CGSize, keepsSquare: Bool) {
        guard let window = liveWindow else { return }
        window.contentMinSize = minimum
        window.contentMaxSize = maximum
        if keepsSquare {
            window.contentAspectRatio = NSSize(width: 1, height: 1)
        } else {
            // Resize increments replace the aspect ratio.
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
        }
    }

    /// Where the traffic lights end, from the window's leading edge.
    var trafficLightsTrailingEdge: Double? {
        guard let zoom = window?.standardWindowButton(.zoomButton) else { return nil }
        return Double(zoom.convert(zoom.bounds, to: nil).maxX)
    }

    var contentSize: CGSize? {
        window.map { $0.contentRect(forFrameRect: $0.frame).size }
    }

    var frame: CGRect? { window?.frame }

    /// The most the content can grow to while the top edge stays put: down to the bottom of the
    /// screen's visible area and across its width.
    var availableContentSize: CGSize? {
        guard let window, let visible = window.screen?.visibleFrame else { return nil }
        let room = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: window.frame.maxY - visible.minY)
        return window.contentRect(forFrameRect: room).size
    }
}

// MARK: - AirPlay

/// The system's AirPlay route picker, drawn in white like the other player buttons.
struct MacAirPlayButton: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.white.withAlphaComponent(NowPlayingText.secondaryOpacity), for: .normal)
        picker.setRoutePickerButtonColor(.white, for: .normalHighlighted)
        picker.setRoutePickerButtonColor(NSColor(Color.minidiscAccent), for: .active)
        picker.setRoutePickerButtonColor(NSColor(Color.minidiscAccent), for: .activeHighlighted)
        picker.setAccessibilityLabel(String(localized: "AirPlay"))
        picker.toolTip = String(localized: "AirPlay")
        return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

// MARK: - Controls over the artwork

/// The MiniPlayer's controls that a keyboard can be on; while one is, they stay on screen.
enum MiniPlayerControl: Hashable {
    case lyrics, queue, volume, favorite, more, shuffle, previous, playPause, next, repeatMode
    /// The bar's button back to the artwork.
    case expand
}

/// Shuffle, Previous, Play/Pause, Next and Repeat in white over the artwork's scrim, as the Music
/// app's MiniPlayer has them; Shuffle and Repeat turn the accent while on.
struct MiniPlayerTransport: View {
    let commands: PlaybackCommandState
    var focus: FocusState<MiniPlayerControl?>.Binding

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        let state = playback.state
        HStack(spacing: 0) {
            button("Shuffle", systemImage: "shuffle", size: 14, isOn: state.isShuffled, control: .shuffle,
                   action: playback.toggleShuffle)
                .disabled(!commands.canShuffle)
            Spacer(minLength: 4)
            button("Previous", systemImage: "backward.fill", size: 20, control: .previous, action: playback.skipToPrevious)
                .disabled(!commands.canSkip)
            Spacer(minLength: 4)
            button(state.wantsPlayback ? "Pause" : "Play", systemImage: state.wantsPlayback ? "pause.fill" : "play.fill",
                   size: 30, control: .playPause, action: playback.togglePlayPause)
                .disabled(!commands.canTogglePlayback)
            Spacer(minLength: 4)
            button("Next", systemImage: "forward.fill", size: 20, control: .next, action: playback.skipToNext)
                .disabled(!commands.canSkip)
            Spacer(minLength: 4)
            button("Repeat", systemImage: state.repeatMode.systemImage, size: 14, isOn: state.repeatMode != .off,
                   control: .repeatMode, action: playback.cycleRepeatMode)
                .disabled(!commands.canRepeat)
        }
        .buttonStyle(.plain)
    }

    private func button(_ title: LocalizedStringKey, systemImage: String, size: Double, isOn: Bool? = nil,
                        control: MiniPlayerControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isOn == true ? Color.minidiscAccent : Color.white)
                .frame(width: max(size * 1.5, 30), height: max(size * 1.3, 28))
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .focused(focus, equals: control)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isOn.map { $0 ? Text("On") : Text("Off") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
        .help(Text(title))
    }
}

/// The playing song's heart as a small glass circle.
struct MacMiniPlayerHeart: View {
    let track: DisplayableSong
    var isShown = true

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            Button {
                playback.setFavorite(toggle.toggled, songs: [track])
            } label: {
                MacGlassCircleLabel(systemImage: toggle.systemImage,
                                    tint: toggle.isFavorite ? Color.minidiscAccent : .white, isShown: isShown)
            }
            .buttonStyle(.plain)
            .disabled(!playback.container.serverState.isOnline)
            .help(Text(toggle.actionTitle))
            .accessibilityLabel(Text("Favorite"))
            .accessibilityValue(Text(toggle.accessibilityValue))
            .accessibilityHint(Text(toggle.actionTitle))
            .accessibilityAddTraits(toggle.isFavorite ? .isSelected : [])
        }
    }
}

// MARK: - Lists

/// A song in the queue, Related and Library lists.
struct MiniPlayerSongRow<Accessory: View>: View {
    let song: DisplayableSong
    var isCurrent = false
    /// Earlier songs are dimmed, as the Music app's history is.
    var isDimmed = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 64, cornerRadius: 4)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.minidiscAccent : .white)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.vertical, 4)
        .opacity(isDimmed ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}

/// A song's length, as the lists show it.
struct MiniPlayerDuration: View {
    let seconds: TimeInterval

    var body: some View {
        Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
    }
}

/// A song's ⋯ menu in a list, with whatever the list adds before the usual song menu.
struct MiniPlayerRowMenu<Extra: View>: View {
    let song: DisplayableSong
    var beforeNavigating: () -> Void
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        Menu {
            extra()
            MacSongMenu(songs: [song], beforeNavigating: beforeNavigating)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
        .accessibilityLabel("More")
        .help("More")
    }
}

extension MiniPlayerRowMenu where Extra == EmptyView {
    init(song: DisplayableSong, beforeNavigating: @escaping () -> Void) {
        self.init(song: song, beforeNavigating: beforeNavigating) { EmptyView() }
    }
}

/// A small-capitals heading inside a pane's list.
struct MiniPlayerListHeading<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

extension MiniPlayerListHeading where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.init(title: title) { EmptyView() }
    }
}

/// The queue as the Music app's MiniPlayer shows it: "Playing Next" (or "Continue Playing" once
/// only Autoplay's songs are left) with "From …" naming the source, Clear and the Autoplay toggle,
/// then the songs played earlier (scroll up for them), the one playing, the listener's songs and
/// Autoplay's. Clicking a song jumps to it; each has a ⋯ menu, and Up Next's songs move and leave
/// through it. Drawn with a lazy stack rather than a List: the MiniPlayer's layouts come and go as
/// its window is resized, and a List (an NSTableView) taken down in the middle of a live resize
/// builds a row for a view graph that's already gone, which crashes.
struct MiniPlayerQueuePane: View {
    var rowInset: Double
    var beforeNavigating: () -> Void

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The queue place of the song last clicked in this list: the jump it starts leaves the list
    /// where it is, since the listener is looking at it, where any other change of song brings
    /// the current one to the top.
    @State private var clickedIndex: Int?

    private static let currentAnchor = MiniPlayerQueueRows.Item.ID.heading(.nowPlaying)

    var body: some View {
        let state = playback.state
        let upcoming = MacQueueEntry.upcoming(in: state)
        let sections = MiniPlayerQueueSections.split(upcoming, queueIndex: { $0.selection.destinationIndex },
                                                     autoplayStart: state.originalQueueEndIndex)
        VStack(spacing: 0) {
            header(state: state, sections: sections, hasUpcoming: !upcoming.isEmpty)
                .padding(.horizontal, rowInset)
                .padding(.top, 10)
                .padding(.bottom, 6)
            if state.currentTrack == nil, upcoming.isEmpty {
                MiniPlayerEmptyTab(title: "Nothing up next", systemImage: "list.bullet")
            } else {
                list(state: state, upcoming: upcoming)
            }
        }
    }

    // MARK: Header

    private func header(state: PlayerState, sections: (requested: [MacQueueEntry], autoplay: [MacQueueEntry]),
                        hasUpcoming: Bool) -> some View {
        let continuePlaying = MiniPlayerQueueSections.headingIsContinuePlaying(
            requestedCount: sections.requested.count, autoplayCount: sections.autoplay.count)
        let autoplayOn = state.isAutoExtendEnabled && state.currentTrack?.isLocalFile != true
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(continuePlaying ? "Continue Playing" : "Playing Next")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let context = state.displayedPlaybackContext {
                    Text("From \(context.title)")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                }
            }
            .lineLimit(1)
            Spacer(minLength: 4)
            Button("Clear", action: playback.clearUpNext)
                .macGlassButton()
                .controlSize(.small)
                .disabled(!hasUpcoming)
                .help("Clear")
            Button {
                playback.setAutoplay(!state.isAutoExtendEnabled)
            } label: {
                Label("Autoplay", systemImage: "infinity")
                    .labelStyle(.iconOnly)
            }
            .macGlassButton(prominent: autoplayOn)
            .controlSize(.small)
            .disabled(state.currentTrack?.isLocalFile == true || state.isLiveStream)
            .accessibilityLabel("Autoplay")
            .accessibilityValue(autoplayOn ? Text("On") : Text("Off"))
            .accessibilityAddTraits(autoplayOn ? .isSelected : [])
            .help("Autoplay")
        }
    }

    // MARK: List

    private func list(state: PlayerState, upcoming: [MacQueueEntry]) -> some View {
        let items = MiniPlayerQueueRows.items(queue: state.queue, currentIndex: state.currentIndex,
                                              isPlaying: state.currentTrack != nil,
                                              autoplayStart: state.originalQueueEndIndex)
        let entries = Dictionary(upcoming.map { ($0.selection.destinationIndex, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // One list in queue order: a song keeps its row as it moves from Up Next to
                    // Now Playing to Back To, so a jump only moves the headings and the highlight.
                    ForEach(items) { item in
                        switch item {
                        case .heading(let heading):
                            MiniPlayerListHeading(title: Self.title(of: heading))
                        case .song(let row):
                            songRow(row, state: state, entry: entries[row.index], upcoming: upcoming)
                        }
                    }
                    if !MiniPlayerQueueRows.hasUpcoming(items) {
                        Text("Nothing up next")
                            .font(.callout)
                            .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, rowInset)
                .padding(.bottom, 10)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state.currentIndex)
            }
            .scrollIndicators(.automatic)
            .onAppear { proxy.scrollTo(Self.currentAnchor, anchor: .top) }
            .onChange(of: state.currentIndex) { _, index in
                // A song clicked here plays where it is; the list stays put under the pointer.
                if let clicked = clickedIndex {
                    clickedIndex = nil
                    if clicked == index { return }
                }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                    proxy.scrollTo(Self.currentAnchor, anchor: .top)
                }
            }
        }
    }

    private static func title(of heading: MiniPlayerQueueRows.Heading) -> LocalizedStringKey {
        switch heading {
        case .backTo: "Back To"
        case .nowPlaying: "Now Playing"
        case .playingNext: "Playing Next"
        case .continuePlaying: "Continue Playing"
        }
    }

    /// Every song's row has the same shape, whichever section it's in, so it isn't rebuilt (nor its
    /// cover reloaded) when a jump moves it to another. The ⋯ menu sits beside the row's button
    /// rather than in it, so the button doesn't take its clicks. Earlier songs are dimmed, the
    /// current one is in the accent, and Up Next's songs move and leave through the menu.
    private func songRow(_ row: MiniPlayerQueueRows.Song, state: PlayerState, entry: MacQueueEntry?,
                         upcoming: [MacQueueEntry]) -> some View {
        let position = row.upcomingPosition
        let queueCount = state.queue.count
        return HStack(spacing: 4) {
            Button {
                jump(to: row, state: state, entry: entry)
            } label: {
                MiniPlayerSongRow(song: row.song, isCurrent: row.role == .current, isDimmed: row.role == .history) {
                    MiniPlayerDuration(seconds: row.song.duration)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(row.role == .current ? Text(verbatim: "") : Text("Play"))
            .accessibilityActions {
                if let position, let entry {
                    Button("Move Up") { move(position, by: -1, in: upcoming, queueCount: queueCount) }
                    Button("Move Down") { move(position, by: 1, in: upcoming, queueCount: queueCount) }
                    Button("Remove from Queue") { playback.removeFromQueue([entry.selection]) }
                }
            }
            MiniPlayerRowMenu(song: row.song, beforeNavigating: beforeNavigating) {
                if let position {
                    queueActions(position, in: upcoming, queueCount: queueCount)
                    Divider()
                }
            }
        }
        .contextMenu {
            if let position {
                queueActions(position, in: upcoming, queueCount: queueCount)
                Divider()
            }
            MacSongMenu(songs: [row.song], beforeNavigating: beforeNavigating)
        }
    }

    /// Plays a song from the list: Up Next's with the request captured when its row was drawn,
    /// an earlier one by its place. Clicking the current song does nothing.
    private func jump(to row: MiniPlayerQueueRows.Song, state: PlayerState, entry: MacQueueEntry?) {
        let selection: QueueTrackSelection?
        switch row.role {
        case .current:
            return
        case .history:
            selection = QueueTrackSelection(playerState: state, destinationIndex: row.index,
                                            destinationTrackID: row.song.id)
        case .requested, .autoplay:
            selection = entry?.selection
        }
        guard let selection else { return }
        clickedIndex = row.index
        playback.jump(to: selection)
    }

    @ViewBuilder
    private func queueActions(_ position: Int, in entries: [MacQueueEntry], queueCount: Int) -> some View {
        Button("Move Up", systemImage: "arrow.up") { move(position, by: -1, in: entries, queueCount: queueCount) }
            .disabled(position == 0)
        Button("Move Down", systemImage: "arrow.down") { move(position, by: 1, in: entries, queueCount: queueCount) }
            .disabled(position == entries.count - 1)
        Button("Remove from Queue", systemImage: "minus.circle") {
            if entries.indices.contains(position) { playback.removeFromQueue([entries[position].selection]) }
        }
    }

    private func move(_ position: Int, by delta: Int, in entries: [MacQueueEntry], queueCount: Int) {
        guard let destination = QueueStep.destination(
            movingPosition: position, by: delta, upcomingCount: entries.count,
            queueIndex: { entries[$0].selection.destinationIndex }, queueCount: queueCount
        ) else { return }
        playback.moveInQueue(entries[position].selection, to: destination)
    }
}

/// Songs like the one playing, each with Add to Queue and the usual song menu, and More for
/// another page.
struct MiniPlayerRelatedList: View {
    let model: MacMiniPlayerModel
    let container: AppContainer
    var rowInset: Double
    var beforeNavigating: () -> Void

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        let track = playback.state.currentTrack
        VStack(spacing: 0) {
            HStack {
                Text("Related Songs")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, rowInset)
            .padding(.top, 10)
            .padding(.bottom, 6)
            Group {
                switch model.relatedState {
                case .idle, .loading:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable:
                    MiniPlayerEmptyTab(title: "No related songs", systemImage: "sparkles")
                case .loaded:
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(model.related) { song in
                                MiniPlayerSongRow(song: song) {
                                    Button {
                                        playback.addToQueue([song])
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .semibold))
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.white)
                                    .accessibilityLabel("Add to Queue")
                                    .help("Add to Queue")
                                    MiniPlayerRowMenu(song: song, beforeNavigating: beforeNavigating)
                                }
                                .contextMenu { MacSongMenu(songs: [song], beforeNavigating: beforeNavigating) }
                            }
                            if model.canLoadMoreRelated {
                                Button("More") {
                                    Task { await model.loadRelated(for: track, container: container, more: true) }
                                }
                                .macGlassButton()
                                .controlSize(.small)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, rowInset)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: track?.id) {
            await model.loadRelated(for: track, container: container)
        }
    }
}

struct MiniPlayerEmptyTab: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }
}
