import SwiftSonic
import SwiftUI

/// Window > MiniPlayer (⌥⌘M): a floating window modelled on the Music app's MiniPlayer. The
/// artwork runs to the window's edges, up under the traffic lights, and nothing sits on it until
/// the pointer comes over: then the traffic lights, a glass capsule at the top right (Lyrics,
/// Queue and Volume) and, over a soft scrim at the bottom, the song, its heart and ⋯ menu, the
/// waveform scrubber and the transport fade in, and fade out again 2.5 seconds after the pointer
/// stops (`PlayerChromeVisibility`).
///
/// The window hugs its content: without a pane it's only the artwork, square, and resizing it
/// scales the artwork; Lyrics or Queue grows it by a pane under the artwork (or beside it, when
/// the screen has no room below, or the window is dragged wide), and closing the pane puts it
/// back as it was. The ⋯ menu also opens the Library and Related Songs panes. Clicking the middle
/// of the artwork, away from the controls, shows the spinning MiniDisc. Opening the MiniPlayer closes Now Playing in the main
/// window, so there's one player on screen; closing it leaves playback alone. It's separate from
/// the menu bar player and Miniamp.
///
/// Nothing in it is a List or Table: its layouts are rebuilt as the window crosses from one shape
/// to another during a live resize, and an NSTableView torn down then crashes.
struct MacMiniPlayer: View {
    static let windowID = "miniPlayer"

    let container: AppContainer
    let interface: MacInterface

    var body: some View {
        let playback = interface.playback(for: container)
        MacMiniPlayerContent(container: container)
            .environment(playback)
            .environment(interface.navigator)
            .environment(interface.playlists(for: container))
            .onAppear {
                MacSpaceKeyMonitor.shared.install(playback: playback)
                // One player at a time: the main window goes back to the library.
                interface.navigator.closeNowPlaying()
            }
    }
}

private struct MacMiniPlayerContent: View {
    let container: AppContainer

    @Environment(MacPlayback.self) private var playback
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @AppStorage("minidisc.mac.miniPlayerPane") private var storedPane: MiniPlayerPane = .upNext
    @AppStorage("minidisc.mac.miniPlayerPaneOpen") private var storedPaneOpen = false
    @AppStorage(MiniPlayerSettings.floatsOnTopKey) private var floatsOnTop = true
    @AppStorage(MiniPlayerSettings.hidesMainWindowKey) private var hidesMainWindow = false
    @State private var lyrics = MacLyricsSession()
    @State private var backdrop = FullPlayerViewModel()
    @State private var model = MacMiniPlayerModel()
    @State private var library: LibraryBrowserModel
    @State private var window = MacWindowHandle()
    @State private var chrome = MacPlayerChrome()
    @State private var sizing = MiniPlayerWindowSizing()
    @State private var showsSpinningDisc = false
    /// Where the song's controls lie over the artwork, which a click there mustn't swap.
    @State private var controlsFrame: CGRect = .null
    @State private var isVolumeShown = false
    /// The window's frame before a pane opened, to put it back exactly where it was.
    @State private var frameBeforeOpening: CGRect?
    /// While the window animates to or from a pane, the layout with the pane, so the artwork
    /// holds its place and only the pane grows or shrinks.
    @State private var transition: MiniPlayerLayout?
    /// The layout the window's limits were last set for.
    @State private var limitsLayout: MiniPlayerLayout?
    @FocusState private var focus: MiniPlayerControl?
    @Namespace private var paneSelection

    /// The row the glass capsule takes above a pane beside the artwork.
    private static let capsuleRow: Double = 44

    init(container: AppContainer) {
        self.container = container
        _library = State(initialValue: LibraryBrowserModel(source: LibraryServiceBrowserSource(library: container.libraryService)))
    }

    private var state: PlayerState { playback.state }
    private var track: DisplayableSong? { state.currentTrack }
    private var canShowLyrics: Bool { playback.commands.canShowLyrics }
    private var hasSong: Bool { track != nil || state.currentRadio != nil }
    private var animation: Animation? { reduceMotion ? nil : .smooth(duration: 0.25) }

    private var coverArtID: String? {
        state.isLiveStream ? state.currentRadio?.coverArt : (track?.coverArtId ?? track?.id)
    }

    private var panel: MiniPlayerPanelState {
        get { MiniPlayerPanelState(pane: storedPane, isOpen: storedPaneOpen) }
        nonmutating set {
            storedPane = newValue.pane
            storedPaneOpen = newValue.isOpen
        }
    }

    private var shownPane: MiniPlayerPane { panel.shownPane(canShowLyrics: canShowLyrics) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layout = transition ?? MiniPlayerLayout.layout(for: size, isPaneOpen: panel.isOpen)
            // Mid-animation the artwork follows the shorter edge, so only the pane grows or shrinks.
            let side = transition != nil ? Double(min(size.width, size.height)) : layout.artworkSide(in: size)
            ZStack(alignment: .topTrailing) {
                switch layout {
                case .compact:
                    artworkStage(side: side)
                        .frame(width: size.width, height: size.height)
                case .tall:
                    VStack(spacing: 0) {
                        artworkStage(side: side)
                            .frame(maxWidth: .infinity)
                        paneArea(layout: .tall, width: Double(size.width))
                    }
                case .wide:
                    HStack(spacing: 0) {
                        artworkStage(side: side)
                            .frame(maxHeight: .infinity)
                        paneArea(layout: .wide, width: max(Double(size.width) - side, 0))
                    }
                }
                paneCapsule
                    .padding(.top, 8)
                    .padding(.trailing, 10)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: layout, initial: true) { _, newLayout in applyLimits(for: newLayout) }
        }
        // The window's least size comes from here (`.contentMinSize`), so with a pane open it must
        // be the tall layout's: room for the song and controls over the artwork as well as the
        // pane. Not while the window animates open or closed, so it doesn't jump.
        .frame(minWidth: MiniPlayerLayout.minimumSide, maxWidth: .infinity,
               minHeight: panel.isOpen && transition == nil
                   ? Double(MiniPlayerLayout.tall.minimumSize.height) : MiniPlayerLayout.minimumSide,
               maxHeight: .infinity)
        // The backdrop runs under the pane and behind the artwork while it loads.
        .background { background.ignoresSafeArea() }
        .ignoresSafeArea()
        .background(MacWindowReader(handle: window) { nsWindow in
            configure(nsWindow)
        })
        .playerChromeTracking(chrome)
        .onChange(of: chrome.isVisible, initial: true) { _, visible in
            window.setTrafficLightsVisible(visible, animated: !reduceMotion)
        }
        .onChange(of: focus) { _, focused in chrome.set(.keyboardFocus, focused != nil) }
        .onChange(of: isVolumeShown) { _, shown in chrome.set(.popover, shown) }
        .onChange(of: floatsOnTop) { _, floats in
            window.window?.level = floats ? .floating : .normal
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow else { return }
            MiniPlayerSettings.miniPlayerDidClose(showMainWindow: showMainWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscFavoritesChanged)) { _ in
            if library.location == .favorites { library.reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: MiniPlayerZoomButton.clickedNotification)) { _ in
            change(storedPane, toggling: true)
        }
        .onChange(of: container.serverState.activeServer?.id) { _, _ in
            library.reset()
        }
        .environment(\.colorScheme, .dark)
        .environment(\.minidiscPlayingAccent, Color.minidiscAccent)
        .foregroundStyle(.white)
        .tint(Color.minidiscAccent)
        .task(id: coverArtID) {
            await backdrop.updateColors(for: coverArtID, discWhenMissing: !state.isLiveStream, colorExtractor: colorExtractor,
                                        container: container, reduceMotion: reduceMotion)
        }
        .task(id: track?.id) {
            await model.load(track, container: container)
        }
        .onChange(of: track?.id) { _, _ in
            // A new song starts on its artwork, as on the iPhone.
            if showsSpinningDisc { showsSpinningDisc = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MiniPlayer")
    }

    // MARK: Backdrop

    /// The artwork's colours darkened under the cap that keeps white text at 7.5:1 and the
    /// secondary white at 4.5:1, behind the pane. Reduce Transparency gets one solid colour.
    @ViewBuilder private var background: some View {
        let colors = PlayerBackgroundPalette.tintedColors(from: backdrop.backgroundColors, accent: .minidiscAccent)
        if reduceTransparency {
            (colors.first ?? .black)
        } else {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Artwork

    /// The artwork, edge to edge, which a click in its middle swaps for the spinning MiniDisc, and
    /// the song's controls over its bottom while the pointer is on the window. The traffic lights
    /// and the glass capsule have the band across its top; clicks there and around the controls
    /// don't swap it.
    private func artworkStage(side: Double) -> some View {
        let topBand = CGRect(x: 0, y: 0, width: side, height: Self.capsuleRow)
        // The scrim fades in above the controls; the click keeps off it too.
        let scrim = controlsFrame.isNull ? CGRect.null
            : CGRect(x: 0, y: controlsFrame.minY - Self.scrimFade, width: side, height: side - controlsFrame.minY + Self.scrimFade)
        return ZStack(alignment: .bottom) {
            MacSpinningDiscArtwork(showsDisc: $showsSpinningDisc, cornerRadius: 0, artworkSize: 1200,
                                   controls: hasSong ? [topBand, controlsFrame] : [topBand],
                                   covered: hasSong ? [scrim] : [])
            if hasSong {
                artworkControls
                    .onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .named(Self.artworkSpace))
                    } action: { frame in
                        controlsFrame = frame
                    }
            }
        }
        .frame(width: side, height: side)
        .coordinateSpace(.named(Self.artworkSpace))
        .clipped()
    }

    private nonisolated static let artworkSpace = "miniPlayerArtwork"

    /// The song with its heart and menu, the waveform scrubber with the times, and the transport,
    /// over a scrim that keeps them legible on any artwork.
    private var artworkControls: some View {
        let isShown = chrome.isVisible
        return VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                songText
                    .allowsHitTesting(false)
                Spacer(minLength: 4)
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        if let track, !track.isLocalFile {
                            MacMiniPlayerHeart(track: track, isShown: isShown)
                                .focused($focus, equals: .favorite)
                        }
                        moreMenu(isShown: isShown)
                    }
                }
            }
            MacWaveformScrubber(envelope: model.waveform, height: 20, isStacked: true, centerLabel: model.formatLabel)
            MiniPlayerTransport(commands: playback.commands, focus: $focus)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            MacArtworkScrim(fadeHeight: Self.scrimFade)
                .padding(.top, -Self.scrimFade)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .playerChromeFade(isShown, reduceMotion: reduceMotion)
    }

    private static let scrimFade: Double = 56

    /// The title in bold above "Artist — Album", as the Music app's MiniPlayer has them.
    private var songText: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let track {
                Text(track.title)
                    .font(.headline)
                MacSongSubtitle(artist: track.artist, album: track.albumName)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
            } else if let radio = state.currentRadio {
                Text(radio.name)
                    .font(.headline)
                Text("Live")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func moreMenu(isShown: Bool) -> some View {
        Menu {
            if let plays = model.playCount, plays > 0 {
                Text("\(plays) plays")
            }
            if let track, !track.isLocalFile {
                FavoriteMatches(.song, id: track.id) { toggle in
                    MacSongMenu(songs: [track], isFavorite: toggle.isFavorite, beforeNavigating: showMainWindow)
                }
            }
            Divider()
            Toggle("Library", isOn: paneBinding(.library))
            Toggle("Related Songs", isOn: paneBinding(.related))
                .disabled(track == nil || track?.isLocalFile == true)
            if panel.isShowing(.lyrics, canShowLyrics: canShowLyrics), lyrics.hasLyrics,
               let viewModel = lyrics.viewModel {
                Divider()
                Toggle("Follow Lyrics", isOn: Binding(get: { viewModel.autoScrollEnabled },
                                                     set: { viewModel.autoScrollEnabled = $0 }))
            }
            Divider()
            Toggle("Float MiniPlayer on Top", isOn: $floatsOnTop)
            Toggle("Hide Main Window with MiniPlayer", isOn: $hidesMainWindow)
            Divider()
            Button("Show Hi-MD", systemImage: "macwindow", action: showMainWindow)
        } label: {
            MacGlassCircleLabel(systemImage: "ellipsis", isShown: isShown)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .focused($focus, equals: .more)
        .accessibilityLabel("More")
        .help("More")
    }

    // MARK: Capsule

    /// Lyrics, Queue and Volume in one glass capsule, the pane on screen filled with the accent.
    private var paneCapsule: some View {
        MacGlassGroup(isShown: chrome.isVisible) {
            MacGlassSegment(title: "Lyrics", systemImage: "quote.bubble",
                            isOn: panel.isShowing(.lyrics, canShowLyrics: canShowLyrics), selection: paneSelection) {
                change(.lyrics, toggling: true)
            }
            .disabled(!canShowLyrics)
            .focused($focus, equals: .lyrics)
            MacGlassSegment(title: "Queue", systemImage: "list.bullet",
                            isOn: panel.isShowing(.upNext, canShowLyrics: canShowLyrics), selection: paneSelection) {
                change(.upNext, toggling: true)
            }
            .focused($focus, equals: .queue)
            MacGlassSegment(title: "Volume", systemImage: volumeSymbol) {
                isVolumeShown.toggle()
            }
            .focused($focus, equals: .volume)
            .popover(isPresented: $isVolumeShown, arrowEdge: .bottom) {
                HStack(spacing: 10) {
                    MacVolumeSlider()
                        .frame(width: 170)
                    MacAirPlayButton()
                        .frame(width: 26, height: 26)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .playerChromeFade(chrome.isVisible, reduceMotion: reduceMotion)
    }

    private var volumeSymbol: String {
        switch playback.volume {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    // MARK: Panes

    @ViewBuilder private func paneArea(layout: MiniPlayerLayout, width: Double) -> some View {
        let rowInset: Double = 14
        Group {
            switch shownPane {
            case .library:
                MacMiniPlayerLibrary(model: library, rowInset: rowInset, beforeNavigating: showMainWindow)
            case .upNext:
                MiniPlayerQueuePane(rowInset: rowInset, beforeNavigating: showMainWindow)
            case .related:
                MiniPlayerRelatedList(model: model, container: container, rowInset: rowInset,
                                      beforeNavigating: showMainWindow)
            case .lyrics:
                // The lines around the one being sung blur and fade, as in Now Playing.
                MacLyricsPane(container: container, session: lyrics, adoptsSessionLyrics: true)
                    .environment(\.lyricsTypography,
                                 .scaled(forWidth: width, minimum: 18, maximum: 28)
                                     .withoutHeaderButtons()
                                     .withDepth(.gentle))
                    .padding(.horizontal, 8)
            }
        }
        // Beside the artwork, the glass capsule has the pane's top row.
        .padding(.top, layout == .wide ? Self.capsuleRow : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func paneBinding(_ pane: MiniPlayerPane) -> Binding<Bool> {
        Binding {
            panel.isShowing(pane, canShowLyrics: canShowLyrics)
        } set: { isOn in
            if isOn {
                change(pane, toggling: false)
            } else if panel.isShowing(pane, canShowLyrics: canShowLyrics) {
                change(pane, toggling: true)
            }
        }
    }

    /// A capsule toggle (`toggling`) or a menu item for `pane`, and what it does to the window:
    /// opening a pane grows a compact window, closing it puts the window back as it was.
    private func change(_ pane: MiniPlayerPane, toggling: Bool) {
        var next = panel
        let change = toggling ? next.toggle(pane, canShowLyrics: canShowLyrics)
            : next.show(pane, canShowLyrics: canShowLyrics)
        guard let content = window.contentSize else {
            panel = next
            return
        }
        switch change {
        case .none:
            return
        case .switchPane:
            withAnimation(animation) { panel = next }
        case .open:
            frameBeforeOpening = window.frame
            let target = sizing.sizeOpeningPane(from: content, available: window.availableContentSize)
            let layout = MiniPlayerLayout.layout(for: target, isPaneOpen: true)
            transition = layout
            panel = next
            applyLimits(for: layout)
            window.resizeContent(to: target, animated: !reduceMotion) {
                transition = nil
            }
        case .close:
            let target = sizing.sizeClosingPane(from: content)
            transition = transition ?? MiniPlayerLayout.layout(for: content, isPaneOpen: true)
            // Down to the compact size; its square limits follow once the pane has gone.
            window.window?.contentMinSize = MiniPlayerLayout.compact.minimumSize
            let finish: @MainActor () -> Void = {
                panel = next
                transition = nil
                applyLimits(for: .compact)
            }
            if let frame = frameBeforeOpening, let nsWindow = window.window,
               nsWindow.contentRect(forFrameRect: frame).size == target {
                window.restoreFrame(frame, animated: !reduceMotion, completion: finish)
            } else {
                window.resizeContent(to: target, animated: !reduceMotion, completion: finish)
            }
            frameBeforeOpening = nil
        }
    }

    // MARK: Window

    private func applyLimits(for layout: MiniPlayerLayout) {
        guard transition == nil || layout == transition, limitsLayout != layout else { return }
        limitsLayout = layout
        window.applyMiniPlayerLimits(for: layout)
    }

    /// No title bar, moved by dragging anywhere, and floating unless turned off. The green button
    /// opens and closes the list below the artwork instead of zooming, which would blow the window
    /// up to fill the screen; enabled, it keeps its colour like the other two.
    private func configure(_ nsWindow: NSWindow) {
        nsWindow.isMovableByWindowBackground = true
        nsWindow.level = floatsOnTop ? .floating : .normal
        if let zoom = nsWindow.standardWindowButton(.zoomButton) {
            zoom.isEnabled = true
            zoom.target = MiniPlayerZoomButton.shared
            zoom.action = #selector(MiniPlayerZoomButton.clicked(_:))
            zoom.toolTip = String(localized: "Show or Hide the List")
        }
        nsWindow.collectionBehavior.insert(.fullScreenNone)
        window.setTrafficLightsVisible(chrome.isVisible, animated: false)
        // A window restored from an earlier launch, or an older version's shapes, fits the pane
        // state: square without a pane.
        if let content = window.contentSize {
            let fitted = MiniPlayerLayout.reconciled(content, isPaneOpen: storedPaneOpen)
            limitsLayout = nil
            applyLimits(for: MiniPlayerLayout.layout(for: fitted, isPaneOpen: storedPaneOpen))
            if abs(fitted.width - content.width) > 1 || abs(fitted.height - content.height) > 1 {
                window.resizeContent(to: fitted, animated: false)
            }
        }
        if hidesMainWindow {
            MiniPlayerSettings.hideMainWindows()
        }
    }

    /// Brings the main window forward, reopening it if it was closed.
    private func showMainWindow() {
        NSApp.activate()
        let main = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(MacMenuBarPlayer.mainWindowID) == true && $0.isVisible }
        if let main {
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: MacMenuBarPlayer.mainWindowID)
        }
    }
}

/// The MiniPlayer's green window button: it shows or hides the list below the artwork, as the
/// glass toggles do, rather than zooming.
@MainActor
final class MiniPlayerZoomButton: NSObject {
    static let shared = MiniPlayerZoomButton()
    static let clickedNotification = Notification.Name("minidisc.miniPlayerZoomClicked")

    @objc func clicked(_ sender: Any?) {
        NotificationCenter.default.post(name: Self.clickedNotification, object: nil)
    }
}
