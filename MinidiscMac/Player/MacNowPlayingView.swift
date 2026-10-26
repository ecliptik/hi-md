import SwiftSonic
import SwiftUI

/// The large player, like the Music app's full-screen player: the artwork, the song and its
/// controls on the left, synced lyrics or the queue on the right, over a backdrop taken from the
/// artwork. It covers the main window, so it fills the screen when the window is full screen.
/// Escape or the close button goes back to the library.
struct MacNowPlayingView: View {
    let container: AppContainer

    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow
    @AppStorage("minidisc.mac.nowPlayingPane") private var requestedPane: NowPlayingSidePane = .lyrics
    /// Both pane buttons are toggles; with neither on, the player stands alone in the middle.
    @AppStorage("minidisc.mac.nowPlayingPaneHidden") private var isPaneHidden = false
    @State private var backdrop = FullPlayerViewModel()
    @State private var showsSpinningDisc = false
    @State private var lyrics = MacLyricsSession()
    @State private var isLyricsFullScreen = false
    @State private var window = MacWindowHandle()
    @State private var titleBarChange: MacTitleBarChange?

    private var state: PlayerState { playback.state }

    private var coverArtID: String? {
        state.isLiveStream ? state.currentRadio?.coverArt : (state.currentTrack?.coverArtId ?? state.currentTrack?.id)
    }

    var body: some View {
        let pane = NowPlayingSidePane.resolved(requestedPane, canShowLyrics: playback.commands.canShowLyrics)
        GeometryReader { proxy in
            let metrics = NowPlayingMetrics(width: proxy.size.width, height: proxy.size.height,
                                            showsPane: !isPaneHidden)
            // The main window is at least 900 points wide, so both halves always fit.
            HStack(spacing: NowPlayingMetrics.columnGap) {
                playerColumn(metrics)
                    .frame(maxWidth: .infinity)
                if !isPaneHidden {
                    sidePane(pane, metrics: metrics)
                        .frame(width: metrics.paneWidth)
                        .frame(maxHeight: .infinity)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, NowPlayingMetrics.horizontalInset)
            .padding(.vertical, NowPlayingMetrics.verticalInset)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .opacity(isLyricsFullScreen ? 0 : 1)
        .allowsHitTesting(!isLyricsFullScreen)
        .accessibilityHidden(isLyricsFullScreen)
        .overlay(alignment: .topLeading) { if !isLyricsFullScreen { windowButtons } }
        .overlay(alignment: .topTrailing) {
            if !isLyricsFullScreen {
                MacVolumeSlider()
                    .frame(width: 180)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
        }
        .overlay(alignment: .bottomTrailing) { if !isLyricsFullScreen { paneButtons(pane) } }
        .overlay {
            if isLyricsFullScreen {
                MacFullScreenLyrics(container: container, session: lyrics, backdropColors: backdrop.backgroundColors) {
                    setLyricsFullScreen(false)
                }
                .transition(.opacity)
            }
        }
        // The backdrop runs under the title bar to the window's top edge.
        .background { background.ignoresSafeArea() }
        .ignoresSafeArea(.container, edges: .top)
        .background(MacWindowReader(handle: window) { window in
            if titleBarChange == nil { titleBarChange = MacTitleBarChange(applyingTo: window) }
        })
        .onDisappear {
            titleBarChange?.restore()
            titleBarChange = nil
        }
        .onChange(of: pane) { _, newPane in
            if newPane != .lyrics, isLyricsFullScreen { setLyricsFullScreen(false) }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .tint(.white)
        .task(id: coverArtID) {
            await backdrop.updateColors(for: coverArtID, colorExtractor: colorExtractor,
                                        container: container, reduceMotion: reduceMotion)
        }
        .onExitCommand(perform: escape)
        .background {
            // Escape closes even when no control inside has focus; full-screen lyrics first.
            Button("Close", action: escape)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    private func escape() {
        if isLyricsFullScreen {
            setLyricsFullScreen(false)
        } else {
            navigator.closeNowPlaying()
        }
    }

    private func setLyricsFullScreen(_ on: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { isLyricsFullScreen = on }
    }

    // MARK: Backdrop

    /// The artwork's colours, darkened so white text keeps its contrast. Reduce Transparency
    /// gets a single solid colour instead of the gradient.
    @ViewBuilder private var background: some View {
        let colors = PlayerBackgroundPalette.tintedColors(from: backdrop.backgroundColors, accent: .minidiscAccent)
        if reduceTransparency {
            (colors.first ?? .black)
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Song and controls

    /// The artwork, the song, a scrubber as wide as the artwork and the transport, all growing
    /// with the window.
    private func playerColumn(_ metrics: NowPlayingMetrics) -> some View {
        VStack(spacing: metrics.columnSpacing) {
            MacSpinningDiscArtwork(showsDisc: $showsSpinningDisc, cornerRadius: 10, artworkSize: 1200)
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            songInfo(metrics)
            MacScrubber(timeStyle: AnyShapeStyle(.white.opacity(NowPlayingText.secondaryOpacity)),
                        timeFont: .system(size: metrics.timeSize, weight: .semibold),
                        timeWidth: metrics.timeSize * 3.8)
            MacTransportControls(commands: playback.commands, isLarge: true,
                                 largeGlyphSize: metrics.transportSize, largePlaySize: metrics.playSize)
                .foregroundStyle(.white)
        }
        .frame(width: metrics.artworkSide)
    }

    private func songInfo(_ metrics: NowPlayingMetrics) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.currentTrack?.title ?? state.currentRadio?.name ?? String(localized: "Not Playing"))
                    .font(.system(size: metrics.titleSize, weight: .bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Group {
                    if let track = state.currentTrack {
                        subtitle(track)
                    } else if state.currentRadio != nil {
                        Text("Live")
                            .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
                    }
                }
                .font(.system(size: metrics.subtitleSize))
            }
            Spacer(minLength: 0)
            if let track = state.currentTrack, !track.isLocalFile {
                songButtons(track, size: metrics.transportSize)
            }
        }
    }

    /// "Artist — Album": each part opens its page and closes the player.
    private func subtitle(_ track: DisplayableSong) -> some View {
        HStack(spacing: 4) {
            if let artist = track.artist, !artist.isEmpty {
                Button(artist) { navigator.showArtist(of: track) }
                    .disabled(track.artistId == nil || track.isLocalFile)
                    .help("Go to Artist")
            }
            if NowPlayingText.subtitle(artist: track.artist, album: track.albumName)?.contains(" — ") == true {
                Text(verbatim: "—")
                    .accessibilityHidden(true)
            }
            if let album = track.albumName, !album.isEmpty {
                Button(album) { navigator.showAlbum(of: track, highlighting: true) }
                    .disabled(track.albumId == nil || track.isLocalFile)
                    .help("Go to Album")
            }
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
    }

    /// The song's heart and its menu.
    private func songButtons(_ track: DisplayableSong, size: Double) -> some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            HStack(spacing: 8) {
                Button {
                    playback.setFavorite(toggle.toggled, songs: [track])
                } label: {
                    Image(systemName: toggle.systemImage)
                        .font(.system(size: size * 0.9))
                        .frame(width: size * 1.6, height: size * 1.6)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .disabled(!playback.container.serverState.isOnline)
                .help(Text(toggle.actionTitle))
                .accessibilityLabel(Text("Favorite"))
                .accessibilityValue(Text(toggle.accessibilityValue))
                .accessibilityHint(Text(toggle.actionTitle))
                .accessibilityAddTraits(toggle.isFavorite ? .isSelected : [])

                Menu {
                    MacSongMenu(songs: [track], isFavorite: toggle.isFavorite)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: size * 0.9))
                        .frame(width: size * 1.6, height: size * 1.6)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
                .help("More")
            }
        }
    }

    // MARK: Lyrics and queue

    /// Lyrics in large bold lines that grow with the pane, as in the Music app.
    @ViewBuilder private func sidePane(_ pane: NowPlayingSidePane, metrics: NowPlayingMetrics) -> some View {
        switch pane {
        case .lyrics:
            // Its follow and full-screen buttons sit with the pane buttons in the corner.
            MacLyricsPane(container: container, session: lyrics)
                .environment(\.lyricsTypography, .scaled(forWidth: metrics.paneWidth).withoutHeaderButtons())
        case .queue:
            MacQueuePane(isOnBackdrop: true)
        }
    }

    // MARK: Window buttons

    private var windowButtons: some View {
        HStack(spacing: 10) {
            Button(action: navigator.closeNowPlaying) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(circleFill, in: Circle())
            }
            .accessibilityLabel("Close Now Playing")
            .help("Close Now Playing")

            Button {
                openWindow(id: MacMiniPlayer.windowID)
            } label: {
                Image(systemName: "pip.enter")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(circleFill, in: Circle())
            }
            .accessibilityLabel("MiniPlayer")
            .help("MiniPlayer")
        }
        .buttonStyle(.plain)
        // Beside the traffic lights, which now sit over the backdrop.
        .padding(.leading, 84)
        .padding(.top, 12)
    }

    private var circleFill: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private func paneButtons(_ pane: NowPlayingSidePane) -> some View {
        HStack(spacing: 6) {
            if !isPaneHidden, pane == .lyrics, lyrics.hasLyrics, let viewModel = lyrics.viewModel {
                lyricsButton("Follow Lyrics", systemImage: "arrow.up.arrow.down", isOn: viewModel.autoScrollEnabled) {
                    viewModel.autoScrollEnabled.toggle()
                }
                lyricsButton("Full Screen Lyrics", systemImage: "arrow.up.left.and.arrow.down.right", isOn: nil) {
                    setLyricsFullScreen(true)
                }
                Divider()
                    .frame(height: 20)
                    .overlay(Color.white.opacity(0.3))
                    .padding(.horizontal, 4)
            }
            paneButton(.lyrics, title: "Lyrics", systemImage: "quote.bubble", shown: pane)
                .disabled(!playback.commands.canShowLyrics)
            paneButton(.queue, title: "Playing Next", systemImage: "list.bullet", shown: pane)
        }
        .padding(20)
    }

    private func lyricsButton(_ title: LocalizedStringKey, systemImage: String, isOn: Bool?,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(isOn == true ? Color.black : Color.white)
                .background(isOn == true ? AnyShapeStyle(Color.white) : circleFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isOn.map { $0 ? Text("On") : Text("Off") } ?? Text(verbatim: ""))
        .accessibilityAddTraits(isOn == true ? .isSelected : [])
        .help(Text(title))
    }

    /// Shows its pane, or hides the side pane when its pane is already showing.
    private func paneButton(_ pane: NowPlayingSidePane, title: LocalizedStringKey, systemImage: String,
                            shown: NowPlayingSidePane) -> some View {
        let isOn = !isPaneHidden && shown == pane
        return Button {
            let next = NowPlayingSidePane.afterClicking(pane, requested: requestedPane, isHidden: isPaneHidden,
                                                        canShowLyrics: playback.commands.canShowLyrics)
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                requestedPane = next.requested
                isPaneHidden = next.isHidden
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .background(isOn ? AnyShapeStyle(Color.white) : circleFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help(Text(title))
    }
}

/// The playing song's artwork, which clicking swaps for the spinning MiniDisc, as tapping the
/// cover does on the iPhone; clicking again brings the artwork back. The disc's hub turns while
/// music plays, unless Reduce Motion is on. With nothing playing it shows the disc at rest.
struct MacSpinningDiscArtwork: View {
    @Binding var showsDisc: Bool
    var cornerRadius: Double = 10
    /// The pixel size asked of the server.
    var artworkSize: Int = 1200

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = playback.state
        let hasArtwork = state.currentTrack != nil || state.currentRadio != nil
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { showsDisc.toggle() }
        } label: {
            ZStack {
                if showsDisc || !hasArtwork {
                    MinidiscLogoView(isSpinning: state.playbackState == .playing)
                        .padding(hasArtwork ? 0 : 12)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                } else {
                    cover(state)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!hasArtwork)
        .accessibilityLabel(showsDisc ? Text("Show Artwork") : Text("Show Spinning Disc"))
        .help(showsDisc ? Text("Show Artwork") : Text("Show Spinning Disc"))
    }

    @ViewBuilder private func cover(_ state: PlayerState) -> some View {
        if let radio = state.currentRadio {
            CoverArtView(id: radio.coverArt ?? radio.id, size: artworkSize, cornerRadius: cornerRadius,
                         placeholderSystemImage: "dot.radiowaves.left.and.right")
        } else if let track = state.currentTrack {
            CoverArtView(id: track.coverArtId ?? track.id, size: artworkSize, cornerRadius: cornerRadius)
                .id(track.coverArtId ?? track.id)
                .transition(reduceMotion ? .identity : .opacity)
        }
    }
}

/// Lets the Now Playing backdrop run under the main window's title bar while it's open, and
/// puts the window back as it was when it closes.
@MainActor
final class MacTitleBarChange {
    private weak var window: NSWindow?
    private let wasTransparent: Bool
    private let hadFullSizeContent: Bool

    init(applyingTo window: NSWindow) {
        self.window = window
        wasTransparent = window.titlebarAppearsTransparent
        hadFullSizeContent = window.styleMask.contains(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
    }

    func restore() {
        guard let window else { return }
        window.titlebarAppearsTransparent = wasTransparent
        if !hadFullSizeContent { window.styleMask.remove(.fullSizeContentView) }
    }
}
