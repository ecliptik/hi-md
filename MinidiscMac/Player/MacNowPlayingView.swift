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
    @State private var backdrop = FullPlayerViewModel()

    private var state: PlayerState { playback.state }

    private var coverArtID: String? {
        state.isLiveStream ? state.currentRadio?.coverArt : (state.currentTrack?.coverArtId ?? state.currentTrack?.id)
    }

    var body: some View {
        let pane = NowPlayingSidePane.resolved(requestedPane, canShowLyrics: playback.commands.canShowLyrics)
        // The main window is at least 900 points wide, so both halves always fit.
        HStack(spacing: 56) {
            playerColumn
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            sidePane(pane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 48)
        .padding(.top, 64)
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var playerColumn: some View {
        VStack(spacing: 22) {
            artwork
                .frame(maxWidth: 440, maxHeight: 440)
                .aspectRatio(1, contentMode: .fit)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            songInfo
            MacScrubber(timeStyle: AnyShapeStyle(.white.opacity(NowPlayingText.secondaryOpacity)))
            MacTransportControls(commands: playback.commands, isLarge: true)
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder private var artwork: some View {
        if let radio = state.currentRadio {
            CoverArtView(id: radio.coverArt ?? radio.id, size: 1200, cornerRadius: 10,
                         placeholderSystemImage: "dot.radiowaves.left.and.right")
        } else if let track = state.currentTrack {
            CoverArtView(id: track.coverArtId ?? track.id, size: 1200, cornerRadius: 10)
                .id(track.coverArtId ?? track.id)
                .transition(reduceMotion ? .identity : .opacity)
        } else {
            MinidiscLogoView(isSpinning: false)
                .padding(48)
        }
    }

    private var songInfo: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.currentTrack?.title ?? state.currentRadio?.name ?? String(localized: "Not Playing"))
                    .font(.title2.bold())
                    .lineLimit(2)
                    .textSelection(.enabled)
                if let track = state.currentTrack {
                    subtitle(track)
                } else if state.currentRadio != nil {
                    Text("Live")
                        .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
                }
            }
            Spacer(minLength: 0)
            if let track = state.currentTrack, !track.isLocalFile {
                songButtons(track)
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
        .font(.title3)
        .lineLimit(1)
        .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
    }

    /// The song's heart and its menu.
    private func songButtons(_ track: DisplayableSong) -> some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            HStack(spacing: 8) {
                Button {
                    playback.setFavorite(toggle.toggled, songs: [track])
                } label: {
                    Image(systemName: toggle.systemImage)
                        .font(.title2)
                        .frame(width: 36, height: 36)
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
                        .font(.title2)
                        .frame(width: 36, height: 36)
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

    @ViewBuilder private func sidePane(_ pane: NowPlayingSidePane) -> some View {
        switch pane {
        case .lyrics:
            MacLyricsPane(container: container)
                .font(.title2.weight(.semibold))
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

    private func paneButton(_ pane: NowPlayingSidePane, title: LocalizedStringKey, systemImage: String,
                            shown: NowPlayingSidePane) -> some View {
        Button {
            requestedPane = pane
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(shown == pane ? Color.black : Color.white)
                .background(shown == pane ? AnyShapeStyle(Color.white) : circleFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(shown == pane ? .isSelected : [])
        .help(Text(title))
    }
}
