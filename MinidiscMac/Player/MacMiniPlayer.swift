import SwiftSonic
import SwiftUI

/// Window > MiniPlayer (⌥⌘M): a floating window modelled on Plexamp's mini player, over a
/// backdrop tinted from the artwork. Its layout follows the window's shape: compact (the artwork
/// above the song), tall (adds the transport, volume and the History, Playing Next, Related and
/// Lyrics tabs) or wide (the artwork beside everything else); the chevron switches between
/// compact and tall. Clicking the artwork shows the spinning MiniDisc. Closing the window leaves
/// playback alone. It's separate from the menu bar player and Winamp mode.
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
            .onAppear { MacSpaceKeyMonitor.shared.install(playback: playback) }
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

    @AppStorage("minidisc.mac.miniPlayerTab") private var storedTab: MiniPlayerTab = .upNext
    @AppStorage("minidisc.mac.miniPlayerLyrics") private var storedShowsLyrics = false
    @AppStorage(MiniPlayerSettings.floatsOnTopKey) private var floatsOnTop = true
    @AppStorage(MiniPlayerSettings.hidesMainWindowKey) private var hidesMainWindow = false
    @State private var lyrics = MacLyricsSession()
    @State private var backdrop = FullPlayerViewModel()
    @State private var model = MacMiniPlayerModel()
    @State private var window = MacWindowHandle()
    @State private var showsSpinningDisc = false
    @State private var isHoveringWindow = false
    @State private var isHoveringArtwork = false

    private var state: PlayerState { playback.state }
    private var track: DisplayableSong? { state.currentTrack }
    private var inset: Double { MiniPlayerLayout.inset }

    private var coverArtID: String? {
        state.isLiveStream ? state.currentRadio?.coverArt : (track?.coverArtId ?? track?.id)
    }

    private var panel: Binding<MiniPlayerPanelState> {
        Binding {
            MiniPlayerPanelState(tab: storedTab, showsLyrics: storedShowsLyrics)
        } set: { newValue in
            storedTab = newValue.tab
            storedShowsLyrics = newValue.showsLyrics
        }
    }

    private var showsLyrics: Bool {
        panel.wrappedValue.isShowingLyrics(canShowLyrics: playback.commands.canShowLyrics)
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MiniPlayerLayout.layout(for: proxy.size)
            let side = layout.artworkSide(in: proxy.size)
            Group {
                switch layout {
                case .compact: compact(side: side)
                case .tall: tall(side: side)
                case .wide: wide(side: side, size: proxy.size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(minWidth: MiniPlayerLayout.minimumWidth, maxWidth: .infinity,
               minHeight: MiniPlayerLayout.minimumHeight, maxHeight: .infinity)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let nsWindow = window.window, note.object as? NSWindow === nsWindow else { return }
            MiniPlayerSettings.miniPlayerDidClose(showMainWindow: showMainWindow)
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
                .padding(.top, inset)
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

    private func tall(side: Double) -> some View {
        VStack(spacing: 0) {
            artworkArea(side: side, layout: .tall)
                .padding(.top, inset)
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
            MiniPlayerTabBar(panel: panel, canShowLyrics: playback.commands.canShowLyrics)
                .padding(.horizontal, inset - 4)
                .padding(.top, 6)
                .padding(.bottom, 6)
            Divider()
                .overlay(Color.white.opacity(0.12))
            tabContent(width: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func wide(side: Double, size: CGSize) -> some View {
        HStack(alignment: .top, spacing: inset) {
            artworkArea(side: side, layout: .wide)
            VStack(alignment: .leading, spacing: 0) {
                // Room for the traffic lights above the text when they show.
                songText(alignment: .leading)
                    .padding(.top, 6)
                albumLine(layout: .wide)
                    .padding(.top, 2)
                MiniPlayerMetadataRow(track: track, model: model)
                    .padding(.top, 4)
                Spacer(minLength: 4)
                MacWaveformScrubber(envelope: model.waveform)
                MiniPlayerTransport(commands: playback.commands, playDiameter: 40)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                if size.height >= 250 {
                    MacVolumeSlider()
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
                toolbar(layout: .wide)
                    .padding(.top, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(inset)
    }

    // MARK: Artwork

    /// The artwork, which clicking swaps for the spinning MiniDisc; in the compact and wide
    /// layouts lyrics take its place while they're on. Compact shows the transport over the
    /// artwork while the pointer is on it (always, with VoiceOver).
    @ViewBuilder
    private func artworkArea(side: Double, layout: MiniPlayerLayout) -> some View {
        // In the tall layout lyrics show in the tab area, so the artwork stays.
        let showsHoverTransport = layout == .compact
        ZStack {
            if showsLyrics, layout != .tall {
                MacLyricsPane(container: container, session: lyrics)
                    .environment(\.lyricsTypography, .scaled(forWidth: side, minimum: 17, maximum: 26).withoutHeaderButtons())
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .transition(.opacity)
            } else {
                MacSpinningDiscArtwork(showsDisc: $showsSpinningDisc, cornerRadius: 8, artworkSize: 600)
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
                    .transition(.opacity)
            }
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

    /// More, the MiniDisc, Shuffle, the chevron, Repeat, Lyrics and AirPlay.
    private func toolbar(layout: MiniPlayerLayout) -> some View {
        let commands = playback.commands
        return HStack(spacing: 0) {
            moreMenu
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
            if layout != .tall {
                MiniPlayerToolbarButton(title: "Lyrics", systemImage: "quote.bubble", isOn: showsLyrics) {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { panel.wrappedValue.toggleLyrics() }
                }
                .disabled(!commands.canShowLyrics)
                Spacer(minLength: 2)
            }
            MacAirPlayButton()
                .frame(width: 28, height: 28)
        }
        .frame(height: 30)
    }

    private var moreMenu: some View {
        Menu {
            if let track, !track.isLocalFile {
                FavoriteMatches(.song, id: track.id) { toggle in
                    MacSongMenu(songs: [track], isFavorite: toggle.isFavorite, beforeNavigating: showMainWindow)
                }
                Divider()
            }
            if showsLyrics, lyrics.hasLyrics, let viewModel = lyrics.viewModel {
                Toggle("Follow Lyrics", isOn: Binding(get: { viewModel.autoScrollEnabled },
                                                     set: { viewModel.autoScrollEnabled = $0 }))
                Divider()
            }
            Toggle("Float MiniPlayer on Top", isOn: $floatsOnTop)
            Toggle("Hide Main Window with MiniPlayer", isOn: $hidesMainWindow)
            Divider()
            Button("Show Hi-MD", systemImage: "macwindow", action: showMainWindow)
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

    // MARK: Tabs

    @ViewBuilder private func tabContent(width: Double) -> some View {
        if showsLyrics {
            MacLyricsPane(container: container, session: lyrics)
                .environment(\.lyricsTypography, .scaled(forWidth: width, minimum: 20, maximum: 30).withoutHeaderButtons())
                .padding(.horizontal, inset - 6)
        } else {
            switch panel.wrappedValue.tab {
            case .history:
                MiniPlayerHistoryList()
            case .upNext:
                MacQueuePane(isOnBackdrop: true)
            case .related:
                MiniPlayerRelatedList(model: model, container: container, beforeNavigating: showMainWindow)
            }
        }
    }

    // MARK: Window

    /// Compact ↔ tall, keeping the window's top edge in place.
    private func toggleExpanded() {
        guard let nsWindow = window.window else { return }
        let content = nsWindow.contentRect(forFrameRect: nsWindow.frame).size
        window.resizeContent(to: MiniPlayerLayout.toggledSize(from: content), animated: !reduceMotion)
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
