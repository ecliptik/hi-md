import AppKit
import AVKit
import SwiftSonic
import SwiftUI

// MARK: - Window

extension MacWindowHandle {
    /// Keeps the window between 3:1 wide and 1:3.2 tall: the largest size follows the current
    /// one, and a window already outside (restored, or from an older version) is brought in.
    func constrainAspect() {
        guard let window else { return }
        let content = window.contentRect(forFrameRect: window.frame).size
        let clamped = MiniPlayerLayout.clamped(content)
        if abs(clamped.width - content.width) > 1 || abs(clamped.height - content.height) > 1 {
            resizeContent(to: clamped, animated: false)
            return
        }
        window.contentMaxSize = MiniPlayerLayout.maximumContentSize(for: content)
        window.contentMinSize = CGSize(width: MiniPlayerLayout.minimumWidth, height: MiniPlayerLayout.minimumHeight)
    }

    var contentSize: CGSize? {
        window.map { $0.contentRect(forFrameRect: $0.frame).size }
    }

    /// The band along the window's top that the close, minimise and zoom buttons take, from
    /// their real frames: down to the lowest one's bottom edge and a little more. Buttons only
    /// faded out (between hovers) still count, so the content doesn't move as they come and go;
    /// with none in the window there's no band.
    func trafficLightsBand() -> Double {
        guard let window else { return MiniPlayerLayout.titleBarBand }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .filter { !$0.isHiddenOrHasHiddenAncestor && $0.window != nil }
        guard !buttons.isEmpty else { return 0 }
        // Window coordinates run up from the bottom edge.
        let lowest = buttons.map { $0.convert($0.bounds, to: nil).minY }.min() ?? window.frame.height
        let band = (Double(window.frame.height - lowest) + 6).rounded()
        return min(max(band, 0), 60)
    }

    /// The most the content can grow to while the top edge stays put: down to the bottom of the
    /// screen's visible area and across its width.
    var availableContentSize: CGSize? {
        guard let window, let visible = window.screen?.visibleFrame else { return nil }
        let room = CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: window.frame.maxY - visible.minY)
        return window.contentRect(forFrameRect: room).size
    }
}


// MARK: - AirPlay

/// The system's AirPlay route picker, drawn in white like the other toolbar buttons.
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

// MARK: - Toolbar buttons

/// A white toolbar glyph that turns the accent colour while its mode is on.
struct MiniPlayerToolbarButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var isOn: Bool? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn == true ? Color.minidiscAccent : Color.white.opacity(NowPlayingText.secondaryOpacity))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isOn.map { $0 ? Text("On") : Text("Off") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
        .help(Text(title))
    }
}

/// Previous, Play/Pause in an accent circle, and Next.
struct MiniPlayerTransport: View {
    let commands: PlaybackCommandState
    /// The play button's diameter; the other glyphs scale with it.
    var playDiameter: Double = 52

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        let state = playback.state
        HStack(spacing: playDiameter * 0.55) {
            Button(action: playback.skipToPrevious) {
                Image(systemName: "backward.fill")
                    .font(.system(size: playDiameter * 0.42))
                    .frame(width: playDiameter * 0.8, height: playDiameter * 0.8)
                    .contentShape(Rectangle())
            }
            .disabled(!commands.canSkip)
            .accessibilityLabel("Previous")
            .help("Previous")

            Button(action: playback.togglePlayPause) {
                Image(systemName: state.wantsPlayback ? "pause.fill" : "play.fill")
                    .font(.system(size: playDiameter * 0.42, weight: .bold))
                    .foregroundStyle(Color.minidiscAccentText)
                    .frame(width: playDiameter, height: playDiameter)
                    .background(Color.minidiscAccent, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(!commands.canTogglePlayback)
            .accessibilityLabel(state.wantsPlayback ? "Pause" : "Play")
            .help(state.wantsPlayback ? "Pause" : "Play")

            Button(action: playback.skipToNext) {
                Image(systemName: "forward.fill")
                    .font(.system(size: playDiameter * 0.42))
                    .frame(width: playDiameter * 0.8, height: playDiameter * 0.8)
                    .contentShape(Rectangle())
            }
            .disabled(!commands.canSkip)
            .accessibilityLabel("Next")
            .help("Next")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

// MARK: - Song details

/// The playing song's heart in the MiniPlayer.
struct MacMiniPlayerHeart: View {
    let track: DisplayableSong

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            Button {
                playback.setFavorite(toggle.toggled, songs: [track])
            } label: {
                Image(systemName: toggle.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(toggle.isFavorite ? Color.minidiscAccent : Color.white.opacity(NowPlayingText.secondaryOpacity))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
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

/// Format, heart and play count, as Plexamp shows codec, rating and plays under the title.
struct MiniPlayerMetadataRow: View {
    let track: DisplayableSong?
    let model: MacMiniPlayerModel

    var body: some View {
        HStack(spacing: 10) {
            if let format = model.formatLabel {
                Text(verbatim: format)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 1))
                    .accessibilityLabel(Text("Format: \(format)"))
            }
            if let track, !track.isLocalFile {
                MacMiniPlayerHeart(track: track)
            }
            if let plays = model.playCount, plays > 0 {
                Text("\(plays) plays")
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
        .frame(height: 20)
    }
}

// MARK: - Tabs

/// Library, Playing Next, Related and Lyrics, in Plexamp's small capitals. A narrow pane, or a
/// language with long names, gets the tabs' icons instead.
struct MiniPlayerTabBar: View {
    /// The pane on screen.
    let selection: MiniPlayerPane
    let canShowLyrics: Bool
    let select: (MiniPlayerPane) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs(showsTitles: true)
            tabs(showsTitles: false)
        }
        .font(.caption.weight(.bold))
        .textCase(.uppercase)
    }

    private func tabs(showsTitles: Bool) -> some View {
        HStack(spacing: 4) {
            tab(.library, title: "Library", systemImage: "books.vertical", showsTitle: showsTitles)
            tab(.upNext, title: "Playing Next", systemImage: "list.bullet", showsTitle: showsTitles)
            tab(.related, title: "Related", systemImage: "sparkles", showsTitle: showsTitles)
            Spacer(minLength: 0)
            tab(.lyrics, title: "Lyrics", systemImage: "quote.bubble", showsTitle: false)
                .disabled(!canShowLyrics)
        }
    }

    private func tab(_ pane: MiniPlayerPane, title: LocalizedStringKey, systemImage: String,
                     showsTitle: Bool) -> some View {
        let isSelected = selection == pane
        // Lyrics keeps the accent it had as the old toggle; the other tabs are a faint capsule.
        let fill: Color = pane == .lyrics ? .minidiscAccent : .white.opacity(0.16)
        let selectedText: Color = pane == .lyrics ? .minidiscAccentText : .white
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { select(pane) }
        } label: {
            Group {
                if showsTitle {
                    Text(title)
                        .lineLimit(1)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? selectedText : Color.white.opacity(NowPlayingText.secondaryOpacity))
            .background(isSelected ? fill : .clear, in: Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(Text(title))
    }
}

/// A song in the Playing Next, Related and Library lists.
struct MiniPlayerSongRow<Accessory: View>: View {
    let song: DisplayableSong
    var isCurrent = false
    /// Earlier songs are dimmed, as Plexamp's history is.
    var isDimmed = false
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 64, cornerRadius: 3)
                .frame(width: 32, height: 32)
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
        .padding(.vertical, 3)
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

/// The queue as Plexamp shows it: the songs played earlier (scroll up for them), the one playing,
/// then Playing Next. Clicking a song jumps to it; Up Next's songs move and leave through their
/// menu. Drawn with a lazy stack rather than a List: the MiniPlayer's layouts come and go as its
/// window is resized, and a List (an NSTableView) taken down in the middle of a live resize
/// builds a row for a view graph that's already gone, which crashes.
struct MiniPlayerQueueList: View {
    var rowInset: Double
    var beforeNavigating: () -> Void

    @Environment(MacPlayback.self) private var playback

    private static let currentAnchor = "now-playing"

    var body: some View {
        let state = playback.state
        let history = Array(QueueHistory.earlier(in: state.queue, currentIndex: state.currentIndex).reversed())
        let upcoming = MacQueueEntry.upcoming(in: state)
        if state.currentTrack == nil, upcoming.isEmpty {
            MiniPlayerEmptyTab(title: "Nothing up next", systemImage: "list.bullet")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !history.isEmpty {
                            MiniPlayerListHeading(title: "Back To")
                            ForEach(history) { entry in
                                historyRow(entry, state: state)
                            }
                        }
                        if let current = state.currentTrack {
                            MiniPlayerListHeading(title: "Now Playing")
                                .id(Self.currentAnchor)
                            MiniPlayerSongRow(song: current, isCurrent: true) {
                                MiniPlayerDuration(seconds: current.duration)
                            }
                            .accessibilityElement(children: .combine)
                            .contextMenu { MacSongMenu(songs: [current], beforeNavigating: beforeNavigating) }
                        }
                        MiniPlayerListHeading(title: "Playing Next") {
                            Button("Clear", action: playback.clearUpNext)
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                                .disabled(upcoming.isEmpty)
                        }
                        if upcoming.isEmpty {
                            Text("Nothing up next")
                                .font(.callout)
                                .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                                .padding(.vertical, 6)
                        }
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { position, entry in
                            upcomingRow(entry, at: position, in: upcoming, queueCount: state.queue.count)
                        }
                    }
                    .padding(.horizontal, rowInset)
                    .padding(.bottom, 8)
                }
                .onAppear { proxy.scrollTo(Self.currentAnchor, anchor: .top) }
                .onChange(of: state.currentIndex) { _, _ in
                    proxy.scrollTo(Self.currentAnchor, anchor: .top)
                }
            }
        }
    }

    private func historyRow(_ entry: QueueHistoryEntry, state: PlayerState) -> some View {
        Button {
            guard let selection = QueueTrackSelection(playerState: state, destinationIndex: entry.index,
                                                      destinationTrackID: entry.song.id) else { return }
            playback.jump(to: selection)
        } label: {
            MiniPlayerSongRow(song: entry.song, isDimmed: true) {
                MiniPlayerDuration(seconds: entry.song.duration)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Play")
        .contextMenu { MacSongMenu(songs: [entry.song], beforeNavigating: beforeNavigating) }
    }

    private func upcomingRow(_ entry: MacQueueEntry, at position: Int, in entries: [MacQueueEntry],
                             queueCount: Int) -> some View {
        Button {
            playback.jump(to: entry.selection)
        } label: {
            MiniPlayerSongRow(song: entry.song) {
                MiniPlayerDuration(seconds: entry.song.duration)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Play")
        .contextMenu {
            Button("Move Up", systemImage: "arrow.up") { move(position, by: -1, in: entries, queueCount: queueCount) }
                .disabled(position == 0)
            Button("Move Down", systemImage: "arrow.down") { move(position, by: 1, in: entries, queueCount: queueCount) }
                .disabled(position == entries.count - 1)
            Button("Remove from Queue", systemImage: "minus.circle") { playback.removeFromQueue([entry.selection]) }
            Divider()
            MacSongMenu(songs: [entry.song], beforeNavigating: beforeNavigating)
        }
        .accessibilityAction(named: "Move Up") { move(position, by: -1, in: entries, queueCount: queueCount) }
        .accessibilityAction(named: "Move Down") { move(position, by: 1, in: entries, queueCount: queueCount) }
        .accessibilityAction(named: "Remove from Queue") { playback.removeFromQueue([entry.selection]) }
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

                                Menu {
                                    MacSongMenu(songs: [song], beforeNavigating: beforeNavigating)
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .rotationEffect(.degrees(90))
                                        .frame(width: 24, height: 24)
                                }
                                .menuStyle(.button)
                                .buttonStyle(.plain)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .foregroundStyle(.white)
                                .accessibilityLabel("More")
                                .help("More")
                            }
                            .contextMenu { MacSongMenu(songs: [song], beforeNavigating: beforeNavigating) }
                        }
                        if model.canLoadMoreRelated {
                            Button("More") {
                                Task { await model.loadRelated(for: track, container: container, more: true) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, rowInset)
                    .padding(.top, 4)
                }
            }
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
