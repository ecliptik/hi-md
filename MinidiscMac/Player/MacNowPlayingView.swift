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
    /// Room left for the traffic lights, none when they're hidden, as in full screen.
    @State private var windowButtonsInset: CGFloat = MacTitleBarChange.trafficLightsInset
    /// The glass buttons and the traffic lights show while the pointer moves and for 2.5 seconds
    /// after, in Now Playing and in full-screen lyrics alike.
    @State private var chrome = MacPlayerChrome()
    /// A button the keyboard is on stays visible.
    @FocusState private var focusedChrome: ChromeControl?
    @Namespace private var paneSelection

    enum ChromeControl: Hashable {
        case close, miniPlayer, volume, follow, exitFullScreen, lyrics, queue
    }

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
        .overlay {
            if isLyricsFullScreen {
                MacFullScreenLyrics(container: container, session: lyrics, backdropColors: backdrop.backgroundColors,
                                    showsSpinningDisc: $showsSpinningDisc)
                    .transition(.opacity)
            }
        }
        // The glass buttons come and go with the pointer, with the traffic lights.
        .overlay(alignment: .topLeading) { windowButtons }
        .overlay(alignment: .topTrailing) { volumeCapsule }
        .overlay(alignment: .bottomTrailing) { paneButtons(pane) }
        .playerChromeTracking(chrome)
        .onChange(of: focusedChrome) { _, focused in chrome.set(.keyboardFocus, focused != nil) }
        .onChange(of: chrome.isVisible) { _, visible in
            window.setTrafficLightsVisible(visible, animated: !reduceMotion)
        }
        .onChange(of: isLyricsFullScreen) { _, _ in chrome.registerActivity() }
        // The backdrop runs under the title bar to the window's top edge.
        .background { background.ignoresSafeArea() }
        .ignoresSafeArea(.container, edges: .top)
        .background(MacWindowReader(handle: window) { window in
            if titleBarChange == nil { titleBarChange = MacTitleBarChange(applyingTo: window) }
            windowButtonsInset = MacTitleBarChange.leadingInset(in: window)
            self.window.setTrafficLightsVisible(chrome.isVisible, animated: false)
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow else { return }
            windowButtonsInset = MacTitleBarChange.leadingInset(in: nsWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow else { return }
            windowButtonsInset = MacTitleBarChange.leadingInset(in: nsWindow)
        }
        .onDisappear {
            titleBarChange?.restore()
            titleBarChange = nil
        }
        .onChange(of: navigator.opensFullScreenLyrics, initial: true) { _, opens in
            // The inspector's full-screen button: open with the lyrics pane, already full screen.
            guard opens else { return }
            navigator.opensFullScreenLyrics = false
            requestedPane = .lyrics
            isPaneHidden = false
            isLyricsFullScreen = true
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

    /// The title on one line with the small heart and menu at its right, and "Artist — Album" on
    /// one line under it, across the whole column.
    private func songInfo(_ metrics: NowPlayingMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(state.currentTrack?.title ?? state.currentRadio?.name ?? String(localized: "Not Playing"))
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let track = state.currentTrack, !track.isLocalFile {
                    MacSongButtons(track: track, buttonSide: metrics.songButtonSize)
                }
            }
            Group {
                if let track = state.currentTrack {
                    subtitle(track)
                } else if state.currentRadio != nil {
                    Text("Live")
                        .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
                }
            }
            .font(.system(size: metrics.subtitleSize))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "Artist — Album": each part opens its page and closes the player. The album truncates
    /// before the artist.
    private func subtitle(_ track: DisplayableSong) -> some View {
        let parts = NowPlayingText.subtitleParts(artist: track.artist, album: track.albumName)
        return HStack(spacing: 4) {
            if let artist = parts.artist {
                Button(artist) { navigator.showArtist(of: track) }
                    .disabled(track.artistId == nil || track.isLocalFile)
                    .help("Go to Artist")
                    .layoutPriority(1)
            }
            if parts.artist != nil, parts.album != nil {
                Text(verbatim: "—")
                    .accessibilityHidden(true)
                    .layoutPriority(1)
            }
            if let album = parts.album {
                Button(album) { navigator.showAlbum(of: track, highlighting: true) }
                    .disabled(track.albumId == nil || track.isLocalFile)
                    .help("Go to Album")
            }
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
    }

    // MARK: Lyrics and queue

    /// Lyrics in large bold lines that grow with the pane, as in the Music app.
    @ViewBuilder private func sidePane(_ pane: NowPlayingSidePane, metrics: NowPlayingMetrics) -> some View {
        switch pane {
        case .lyrics:
            // Its follow and full-screen buttons sit with the pane buttons in the corner. The
            // lines around the one being sung blur and fade a little, as full screen's do more.
            MacLyricsPane(container: container, session: lyrics)
                .environment(\.lyricsTypography,
                             .scaled(forWidth: metrics.paneWidth).withoutHeaderButtons().withDepth(.gentle))
        case .queue:
            MacQueuePane(isOnBackdrop: true)
        }
    }

    // MARK: Window buttons

    /// Close and MiniPlayer in one glass capsule at the top left, clear of the traffic lights.
    private var windowButtons: some View {
        MacGlassGroup(isShown: chrome.isVisible) {
            MacGlassSegment(title: "Close Now Playing", systemImage: "xmark", side: Self.buttonSide) {
                navigator.closeNowPlaying()
            }
            .focused($focusedChrome, equals: .close)
            MacGlassSegment(title: "MiniPlayer", systemImage: "pip.enter", side: Self.buttonSide) {
                // The MiniPlayer takes over: the window goes back to the library, even when the
                // MiniPlayer was already open and only comes forward.
                navigator.closeNowPlaying()
                openWindow(id: MacMiniPlayer.windowID)
            }
            .focused($focusedChrome, equals: .miniPlayer)
        }
        .playerChromeFade(chrome.isVisible, reduceMotion: reduceMotion)
        // Beside the traffic lights, which now sit over the backdrop, or at the edge without them.
        .padding(.leading, windowButtonsInset)
        .padding(.top, 10)
    }

    /// The volume slider in a glass capsule at the top right.
    private var volumeCapsule: some View {
        MacVolumeSlider()
            .focused($focusedChrome, equals: .volume)
            .frame(width: 170)
            .padding(.horizontal, 12)
            .frame(height: Self.buttonSide + 6)
            .macGlass(in: Capsule(), isShown: chrome.isVisible)
            .playerChromeFade(chrome.isVisible, reduceMotion: reduceMotion)
            .padding(.horizontal, 20)
            .padding(.top, 10)
    }

    private static let buttonSide: Double = 28

    /// Follow Lyrics and full screen beside the Lyrics and Playing Next toggles, one glass group
    /// with the toggles that are on filled with the accent. In full-screen lyrics Lyrics is on
    /// and takes the view back, as Escape and Exit Full Screen do.
    private func paneButtons(_ pane: NowPlayingSidePane) -> some View {
        let showsLyricsTools = !isPaneHidden && pane == .lyrics && lyrics.hasLyrics && lyrics.viewModel != nil
        return MacGlassGroup(isShown: chrome.isVisible) {
            if showsLyricsTools, let viewModel = lyrics.viewModel {
                MacGlassSegment(title: "Follow Lyrics", systemImage: "arrow.up.arrow.down",
                                isOn: viewModel.autoScrollEnabled, side: Self.buttonSide) {
                    viewModel.autoScrollEnabled.toggle()
                }
                .focused($focusedChrome, equals: .follow)
                if isLyricsFullScreen {
                    MacGlassSegment(title: "Exit Full Screen Lyrics", systemImage: "arrow.down.right.and.arrow.up.left",
                                    side: Self.buttonSide) {
                        setLyricsFullScreen(false)
                    }
                    .focused($focusedChrome, equals: .exitFullScreen)
                } else {
                    MacGlassSegment(title: "Full Screen Lyrics", systemImage: "arrow.up.left.and.arrow.down.right",
                                    side: Self.buttonSide) {
                        setLyricsFullScreen(true)
                    }
                    .focused($focusedChrome, equals: .exitFullScreen)
                }
                Divider()
                    .frame(height: Self.buttonSide * 0.6)
                    .overlay(Color.white.opacity(0.3))
                    .padding(.horizontal, 4)
            }
            if isLyricsFullScreen {
                MacGlassSegment(title: "Lyrics", systemImage: "quote.bubble", isOn: true, side: Self.buttonSide,
                                selection: paneSelection) {
                    setLyricsFullScreen(false)
                }
                .focused($focusedChrome, equals: .lyrics)
                .accessibilityHint("Exits full-screen lyrics")
            } else {
                paneButton(.lyrics, title: "Lyrics", systemImage: "quote.bubble", shown: pane)
                    .disabled(!playback.commands.canShowLyrics)
                    .focused($focusedChrome, equals: .lyrics)
            }
            paneButton(.queue, title: "Playing Next", systemImage: "list.bullet", shown: pane)
                .focused($focusedChrome, equals: .queue)
        }
        .playerChromeFade(chrome.isVisible, reduceMotion: reduceMotion)
        .padding(20)
    }

    /// Shows its pane, or hides the side pane when its pane is already showing.
    private func paneButton(_ pane: NowPlayingSidePane, title: LocalizedStringKey, systemImage: String,
                            shown: NowPlayingSidePane) -> some View {
        MacGlassSegment(title: title, systemImage: systemImage, isOn: !isPaneHidden && shown == pane,
                        side: Self.buttonSide, selection: paneSelection) {
            let next = NowPlayingSidePane.afterClicking(pane, requested: requestedPane, isHidden: isPaneHidden,
                                                        canShowLyrics: playback.commands.canShowLyrics)
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                requestedPane = next.requested
                isPaneHidden = next.isHidden
            }
        }
    }
}

/// The playing song's heart and its menu, beside the title in Now Playing and full-screen lyrics.
struct MacSongButtons: View {
    let track: DisplayableSong
    /// Each button's side; the glyph is a little over half of it.
    let buttonSide: Double

    private var glyphSize: Double { (buttonSide * 0.56).rounded() }

    @Environment(MacPlayback.self) private var playback

    var body: some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            HStack(spacing: 8) {
                Button {
                    playback.setFavorite(toggle.toggled, songs: [track])
                } label: {
                    Image(systemName: toggle.systemImage)
                        .font(.system(size: glyphSize))
                        .frame(width: buttonSide, height: buttonSide)
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
                        .font(.system(size: glyphSize))
                        .frame(width: buttonSide, height: buttonSide)
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

    static let trafficLightsInset: CGFloat = 84
    static let edgeInset: CGFloat = 20

    /// How far the window's own buttons push content from the leading edge: past the traffic
    /// lights, even while Now Playing has faded them out, and to the edge in full screen, where
    /// they're hidden.
    static func leadingInset(in window: NSWindow) -> CGFloat {
        guard !window.styleMask.contains(.fullScreen),
              let zoom = window.standardWindowButton(.zoomButton),
              !zoom.isHiddenOrHasHiddenAncestor
        else { return edgeInset }
        return max(trafficLightsInset, zoom.convert(zoom.bounds, to: nil).maxX + 16)
    }

    func restore() {
        guard let window else { return }
        window.titlebarAppearsTransparent = wasTransparent
        if !hadFullSizeContent { window.styleMask.remove(.fullSizeContentView) }
        // Now Playing fades the traffic lights with its buttons; the library always has them.
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.alphaValue = 1
        }
    }
}
