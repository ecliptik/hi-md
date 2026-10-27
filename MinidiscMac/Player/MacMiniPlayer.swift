import SwiftSonic
import SwiftUI

/// Window > MiniPlayer (⌥⌘M): a floating window modelled on Plexamp's mini player, over a
/// backdrop tinted from the artwork. Its layout follows the window's shape: compact (the artwork
/// above the song), tall (adds the transport, volume and the Library, Playing Next, Related and
/// Lyrics tabs) or wide (the artwork beside everything else, with a pane between the song and
/// the controls when one is open). The chevron switches between compact and tall; the toolbar's
/// Library and Lyrics buttons open their pane, growing a compact window to show it. Clicking the
/// artwork shows the spinning MiniDisc. Opening it closes Now Playing in the main window, so
/// there's one player on screen; closing it leaves playback alone. It's separate from the menu
/// bar player and Winamp mode.
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
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    @AppStorage("minidisc.mac.miniPlayerPane") private var storedPane: MiniPlayerPane = .upNext
    @AppStorage("minidisc.mac.miniPlayerPaneOpen") private var storedPaneOpen = false
    @AppStorage(MiniPlayerSettings.floatsOnTopKey) private var floatsOnTop = true
    @AppStorage(MiniPlayerSettings.hidesMainWindowKey) private var hidesMainWindow = false
    @State private var lyrics = MacLyricsSession()
    @State private var backdrop = FullPlayerViewModel()
    @State private var model = MacMiniPlayerModel()
    @State private var library: LibraryBrowserModel
    @State private var window = MacWindowHandle()
    @State private var showsSpinningDisc = false
    @State private var isHoveringWindow = false
    @State private var isHoveringArtwork = false
    /// The band the traffic lights take along the top, measured from the window's buttons.
    @State private var topInset = MiniPlayerLayout.titleBarBand
    /// The compact window's size before a Library or Lyrics click grew it, to go back to.
    @State private var sizeBeforeGrowing: CGSize?

    init(container: AppContainer) {
        self.container = container
        _library = State(initialValue: LibraryBrowserModel(source: LibraryServiceBrowserSource(library: container.libraryService)))
    }

    private var state: PlayerState { playback.state }
    private var track: DisplayableSong? { state.currentTrack }
    private var inset: Double { MiniPlayerLayout.inset }
    private var topSpace: Double { MiniPlayerLayout.topSpace(topInset) }
    private var canShowLyrics: Bool { playback.commands.canShowLyrics }

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
            let layout = MiniPlayerLayout.layout(for: proxy.size)
            let side = layout.artworkSide(in: proxy.size, topInset: topInset)
            Group {
                switch layout {
                case .compact: compact(side: side)
                case .tall: tall(side: side, width: proxy.size.width)
                case .wide: wide(side: side, size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(minWidth: MiniPlayerLayout.minimumWidth, maxWidth: .infinity,
               minHeight: MiniPlayerLayout.minimumHeight, maxHeight: .infinity)
        // The backdrop runs under the traffic lights' band, so the window still looks borderless.
        .background { background.ignoresSafeArea() }
        .ignoresSafeArea()
        .background(MacWindowReader(handle: window) { nsWindow in
            configure(nsWindow)
        })
        .onHover { hovering in
            isHoveringWindow = hovering
            window.setTrafficLightsVisible(hovering || voiceOverEnabled, animated: !reduceMotion)
        }
        .onChange(of: floatsOnTop) { _, floats in
            window.window?.level = floats ? .floating : .normal
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow else { return }
            window.constrainAspect()
            measureTopInset()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow,
                  let size = window.contentSize else { return }
            // Dragged back to compact by hand: a later click grows it from here.
            if MiniPlayerLayout.layout(for: size) == .compact { sizeBeforeGrowing = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow else { return }
            MiniPlayerSettings.miniPlayerDidClose(showMainWindow: showMainWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .minidiscFavoritesChanged)) { _ in
            if library.location == .favorites { library.reload() }
        }
        .onChange(of: container.serverState.activeServer?.id) { _, _ in
            library.reset()
        }
        .environment(\.colorScheme, .dark)
        .environment(\.minidiscPlayingAccent, Color.minidiscAccent)
        .foregroundStyle(.white)
        .tint(Color.minidiscAccent)
        .task(id: coverArtID) {
            await backdrop.updateColors(for: coverArtID, colorExtractor: colorExtractor,
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
    /// secondary white at 4.5:1. Reduce Transparency gets one solid colour.
    @ViewBuilder private var background: some View {
        let colors = PlayerBackgroundPalette.tintedColors(from: backdrop.backgroundColors, accent: .minidiscAccent)
        if reduceTransparency {
            (colors.first ?? .black)
        } else {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }

    // MARK: Layouts

    private func compact(side: Double) -> some View {
        VStack(spacing: 0) {
            artworkArea(side: side, layout: .compact)
                .padding(.top, topSpace)
            Spacer(minLength: 10)
            MacWaveformScrubber(envelope: model.waveform)
                .padding(.horizontal, inset)
            songText(alignment: .center)
                .padding(.horizontal, inset)
                .padding(.top, 6)
            MiniPlayerMetadataRow(track: track, model: model)
                .padding(.top, 4)
            Spacer(minLength: 4)
            toolbar(layout: .compact)
                .padding(.horizontal, inset - 4)
                .padding(.bottom, 8)
        }
    }

    private func tall(side: Double, width: Double) -> some View {
        VStack(spacing: 0) {
            artworkArea(side: side, layout: .tall)
                .padding(.top, topSpace)
            MacWaveformScrubber(envelope: model.waveform)
                .padding(.horizontal, inset)
                .padding(.top, 10)
            songText(alignment: .center)
                .padding(.horizontal, inset)
                .padding(.top, 6)
            albumLine(layout: .tall)
                .padding(.horizontal, inset)
                .padding(.top, 2)
            MiniPlayerMetadataRow(track: track, model: model)
                .padding(.top, 4)
            MiniPlayerTransport(commands: playback.commands, playDiameter: 52)
                .padding(.top, 8)
            MacVolumeSlider()
                .padding(.horizontal, inset + 12)
                .padding(.top, 8)
            toolbar(layout: .tall)
                .padding(.horizontal, inset - 4)
                .padding(.top, 6)
            paneArea(width: width, layout: .tall)
        }
    }

    /// The artwork on the left; on the right the song at the top and the controls at the
    /// bottom, with the open pane filling the space between them.
    private func wide(side: Double, size: CGSize) -> some View {
        let showsPane = MiniPlayerLayout.wide.showsPane(isOpen: panel.isOpen)
        let columnWidth = max(Double(size.width) - side - 3 * inset, 0)
        return HStack(alignment: .top, spacing: inset) {
            artworkArea(side: side, layout: .wide)
            VStack(alignment: .leading, spacing: 0) {
                songText(alignment: .leading)
                if size.height >= 240 {
                    albumLine(layout: .wide)
                        .padding(.top, 2)
                }
                MiniPlayerMetadataRow(track: track, model: model)
                    .padding(.top, 4)
                if showsPane {
                    paneArea(width: columnWidth, layout: .wide)
                        .padding(.vertical, 6)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 4)
                }
                MacWaveformScrubber(envelope: model.waveform)
                MiniPlayerTransport(commands: playback.commands, playDiameter: 40)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                if size.height >= (showsPane ? 440 : 250) {
                    MacVolumeSlider()
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                toolbar(layout: .wide)
                    .padding(.top, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, inset)
        .padding(.bottom, inset)
        .padding(.top, topSpace)
    }

    // MARK: Artwork

    /// The artwork, which clicking swaps for the spinning MiniDisc. Compact shows the transport
    /// over the artwork while the pointer is on it (always, with VoiceOver). The panes never
    /// cover it.
    private func artworkArea(side: Double, layout: MiniPlayerLayout) -> some View {
        let showsHoverTransport = layout == .compact
        return MacSpinningDiscArtwork(showsDisc: $showsSpinningDisc, cornerRadius: 8, artworkSize: 600)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .overlay {
                if showsHoverTransport, track != nil || state.currentRadio != nil {
                    hoverTransport
                        .opacity(isHoveringArtwork || voiceOverEnabled ? 1 : 0)
                        .allowsHitTesting(isHoveringArtwork || voiceOverEnabled)
                }
            }
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHoveringArtwork = hovering }
            }
            .frame(width: side, height: side)
    }

    private var hoverTransport: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .allowsHitTesting(false)
            MiniPlayerTransport(commands: playback.commands, playDiameter: 44)
                .padding(.bottom, 14)
        }
    }

    // MARK: Song

    /// Artist in regular weight above the title in bold, as Plexamp has them.
    private func songText(alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: 1) {
            if let track {
                Text(track.artist ?? "")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                Text(track.title)
                    .font(.headline)
            } else if let radio = state.currentRadio {
                Text("Live")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                Text(radio.name)
                    .font(.headline)
            } else {
                Text("Not Playing")
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
            }
        }
        .lineLimit(1)
        .multilineTextAlignment(textAlignment)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Album (Year)".
    @ViewBuilder private func albumLine(layout: MiniPlayerLayout) -> some View {
        if let album = track?.albumName, !album.isEmpty {
            Group {
                if let year = model.year, year > 0 {
                    Text(verbatim: "\(album) (\(String(year)))")
                } else {
                    Text(verbatim: album)
                }
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: layout == .wide ? .leading : .center)
        }
    }

    // MARK: Toolbar

    /// More, the MiniDisc, Shuffle, the chevron, Repeat, Library, Lyrics and AirPlay.
    private func toolbar(layout: MiniPlayerLayout) -> some View {
        let commands = playback.commands
        return HStack(spacing: 0) {
            moreMenu(layout: layout)
            Spacer(minLength: 2)
            MiniPlayerToolbarButton(title: showsSpinningDisc ? "Show Artwork" : "Show Spinning Disc",
                                    systemImage: "opticaldisc", isOn: showsSpinningDisc) {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { showsSpinningDisc.toggle() }
            }
            .disabled(track == nil && state.currentRadio == nil)
            Spacer(minLength: 2)
            MiniPlayerToolbarButton(title: "Shuffle", systemImage: "shuffle", isOn: state.isShuffled,
                                    action: playback.toggleShuffle)
                .disabled(!commands.canShuffle)
            Spacer(minLength: 2)
            MiniPlayerToolbarButton(title: layout.expands ? "Show Lyrics and Queue" : "Hide Lyrics and Queue",
                                    systemImage: layout.expands ? "chevron.down" : "chevron.up") {
                toggleExpanded()
            }
            Spacer(minLength: 2)
            MiniPlayerToolbarButton(title: "Repeat", systemImage: state.repeatMode.systemImage,
                                    isOn: state.repeatMode != .off, action: playback.cycleRepeatMode)
                .disabled(!commands.canRepeat)
            Spacer(minLength: 2)
            MiniPlayerToolbarButton(title: "Library", systemImage: "books.vertical",
                                    isOn: panel.isShowing(.library, in: layout, canShowLyrics: canShowLyrics)) {
                togglePane(.library, layout: layout)
            }
            Spacer(minLength: 2)
            MiniPlayerToolbarButton(title: "Lyrics", systemImage: "quote.bubble",
                                    isOn: panel.isShowing(.lyrics, in: layout, canShowLyrics: canShowLyrics)) {
                togglePane(.lyrics, layout: layout)
            }
            .disabled(!canShowLyrics)
            Spacer(minLength: 2)
            MacAirPlayButton()
                .frame(width: 28, height: 28)
        }
        .frame(height: 30)
    }

    private func moreMenu(layout: MiniPlayerLayout) -> some View {
        Menu {
            if let track, !track.isLocalFile {
                FavoriteMatches(.song, id: track.id) { toggle in
                    MacSongMenu(songs: [track], isFavorite: toggle.isFavorite, beforeNavigating: showMainWindow)
                }
                Divider()
            }
            if panel.isShowing(.lyrics, in: layout, canShowLyrics: canShowLyrics), lyrics.hasLyrics,
               let viewModel = lyrics.viewModel {
                Toggle("Follow Lyrics", isOn: Binding(get: { viewModel.autoScrollEnabled },
                                                     set: { viewModel.autoScrollEnabled = $0 }))
                Divider()
            }
            Toggle("Float MiniPlayer on Top", isOn: $floatsOnTop)
            Toggle("Hide Main Window with MiniPlayer", isOn: $hidesMainWindow)
            Divider()
            Button("Show Minidisc", systemImage: "macwindow", action: showMainWindow)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
        .accessibilityLabel("More")
        .help("More")
    }

    // MARK: Panes

    /// The tabs and the pane under them: the bottom of the tall layout, or between the song and
    /// the controls in the wide one.
    private func paneArea(width: Double, layout: MiniPlayerLayout) -> some View {
        let isTall = layout == .tall
        return VStack(spacing: 0) {
            MiniPlayerTabBar(selection: shownPane, canShowLyrics: canShowLyrics) { pane in
                panel.select(pane)
            }
            .padding(.horizontal, isTall ? inset - 4 : 0)
            .padding(.top, isTall ? 6 : 0)
            .padding(.bottom, 6)
            Divider()
                .overlay(Color.white.opacity(0.12))
            paneContent(width: width, layout: layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    @ViewBuilder private func paneContent(width: Double, layout: MiniPlayerLayout) -> some View {
        let isTall = layout == .tall
        let rowInset = isTall ? inset : 0
        switch shownPane {
        case .library:
            MacMiniPlayerLibrary(model: library, rowInset: rowInset, beforeNavigating: showMainWindow)
        case .upNext:
            MiniPlayerQueueList(rowInset: rowInset, beforeNavigating: showMainWindow)
        case .related:
            MiniPlayerRelatedList(model: model, container: container, rowInset: rowInset, beforeNavigating: showMainWindow)
        case .lyrics:
            // The lines around the one being sung blur and fade, as in Now Playing.
            MacLyricsPane(container: container, session: lyrics, adoptsSessionLyrics: true)
                .environment(\.lyricsTypography,
                             .scaled(forWidth: width, minimum: isTall ? 20 : 17, maximum: isTall ? 28 : 26)
                                 .withoutHeaderButtons()
                                 .withDepth(.gentle))
                .padding(.horizontal, isTall ? inset - 6 : -4)
        }
    }

    /// The toolbar's Library and Lyrics buttons.
    private func togglePane(_ pane: MiniPlayerPane, layout: MiniPlayerLayout) {
        guard let content = window.contentSize else { return }
        var next = panel
        let change = next.toggle(pane, in: layout, canShowLyrics: canShowLyrics,
                                 grewFromCompact: sizeBeforeGrowing != nil)
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { panel = next }
        switch change {
        case .show:
            if let taller = MiniPlayerLayout.wideSizeShowingPane(from: content, topInset: topInset) {
                window.resizeContent(to: taller, animated: !reduceMotion)
            }
        case .close:
            break
        case .grow:
            sizeBeforeGrowing = content
            let grown = MiniPlayerLayout.grownSize(fromCompact: content, available: window.availableContentSize,
                                                   topInset: topInset)
            window.resizeContent(to: grown, animated: !reduceMotion)
        case .collapse:
            let compact = sizeBeforeGrowing ?? MiniPlayerLayout.collapsedSize(from: content, topInset: topInset)
            sizeBeforeGrowing = nil
            window.resizeContent(to: compact, animated: !reduceMotion)
        }
    }

    // MARK: Window

    /// Compact ↔ tall, keeping the window's top edge in place.
    private func toggleExpanded() {
        guard let content = window.contentSize else { return }
        sizeBeforeGrowing = nil
        window.resizeContent(to: MiniPlayerLayout.toggledSize(from: content, topInset: topInset), animated: !reduceMotion)
    }

    /// The traffic lights' band, when the buttons have moved or come and gone.
    private func measureTopInset() {
        let band = window.trafficLightsBand()
        if abs(band - topInset) > 0.5 { topInset = band }
    }

    /// No title bar, moved by dragging anywhere, floating unless turned off, and no zoom: a
    /// double-click on the backdrop would otherwise blow the card up to a full-screen strip.
    private func configure(_ nsWindow: NSWindow) {
        nsWindow.isMovableByWindowBackground = true
        nsWindow.level = floatsOnTop ? .floating : .normal
        nsWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        nsWindow.collectionBehavior.insert(.fullScreenNone)
        window.setTrafficLightsVisible(isHoveringWindow || voiceOverEnabled, animated: false)
        window.constrainAspect()
        measureTopInset()
        // The title bar lays its buttons out after the window first shows.
        Task { @MainActor in measureTopInset() }
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
