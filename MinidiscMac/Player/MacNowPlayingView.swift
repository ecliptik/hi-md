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
        .background { background }
        .overlay(alignment: .topLeading) { windowButtons }
        .overlay(alignment: .topTrailing) {
            MacVolumeSlider()
                .frame(width: 180)
                .padding(20)
        }
        .overlay(alignment: .bottomTrailing) { paneButtons(pane) }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .tint(.white)
        .task(id: coverArtID) {
            await backdrop.updateColors(for: coverArtID, colorExtractor: colorExtractor,
                                        container: container, reduceMotion: reduceMotion)
        }
        .onExitCommand { navigator.closeNowPlaying() }
        .background {
            // Escape closes even when no control inside has focus.
            Button("Close", action: navigator.closeNowPlaying)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now Playing")
    }

    // MARK: Backdrop

    /// The artwork's colours, darkened so white text keeps its contrast. Reduce Transparency
    /// gets a single solid colour instead of the gradient.
    @ViewBuilder private var background: some View {
        let colors = PlayerBackgroundPalette.colors(from: backdrop.backgroundColors)
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
            MacLyricsPane(container: container)
                .environment(\.lyricsTypography, .scaled(forWidth: metrics.paneWidth))
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
        .padding(20)
    }

    private var circleFill: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(.ultraThinMaterial)
    }

    private func paneButtons(_ pane: NowPlayingSidePane) -> some View {
        HStack(spacing: 6) {
            paneButton(.lyrics, title: "Lyrics", systemImage: "quote.bubble", shown: pane)
                .disabled(!playback.commands.canShowLyrics)
            paneButton(.queue, title: "Playing Next", systemImage: "list.bullet", shown: pane)
        }
        .padding(20)
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
