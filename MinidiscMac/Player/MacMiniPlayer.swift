import SwiftSonic
import SwiftUI

/// Window > MiniPlayer (⌥⌘M): a small floating window with the artwork, the song, its heart, the
/// transport and the scrubber, which expands to show synced lyrics or the queue. Closing it
/// leaves playback alone; the Music app's MiniPlayer is the model. It's separate from the menu
/// bar player and Winamp mode.
struct MacMiniPlayer: View {
    static let windowID = "miniPlayer"

    let container: AppContainer
    let interface: MacInterface

    @AppStorage("minidisc.mac.miniPlayerExpanded") private var isExpanded = false
    @AppStorage("minidisc.mac.miniPlayerPane") private var requestedPane: NowPlayingSidePane = .lyrics
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let playback = interface.playback(for: container)
        let state = container.playerState
        let pane = NowPlayingSidePane.resolved(requestedPane, canShowLyrics: playback.commands.canShowLyrics)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                artwork(state)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.currentTrack?.title ?? state.currentRadio?.name ?? String(localized: "Not Playing"))
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle = NowPlayingText.subtitle(artist: state.currentTrack?.artist,
                                                              album: state.currentTrack?.albumName) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        if let track = state.currentTrack, !track.isLocalFile {
                            MacMiniPlayerHeart(track: track)
                        }
                        Spacer(minLength: 0)
                        Button {
                            showMainWindow()
                        } label: {
                            Image(systemName: "macwindow")
                        }
                        .accessibilityLabel("Show Minidisc")
                        .help("Show Minidisc")
                        Button {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { isExpanded.toggle() }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .accessibilityLabel(isExpanded ? "Hide Lyrics and Queue" : "Show Lyrics and Queue")
                        .help(isExpanded ? "Hide Lyrics and Queue" : "Show Lyrics and Queue")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(12)

            MacScrubber()
                .padding(.horizontal, 12)
            MacTransportControls(commands: playback.commands)
                .padding(.top, 4)
                .padding(.bottom, 10)

            if isExpanded {
                Divider()
                Picker("Show", selection: $requestedPane) {
                    Text("Lyrics").tag(NowPlayingSidePane.lyrics)
                    Text("Playing Next").tag(NowPlayingSidePane.queue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                .onChange(of: playback.commands.canShowLyrics) { _, canShow in
                    if !canShow, requestedPane == .lyrics { requestedPane = .queue }
                }
                switch pane {
                case .lyrics:
                    MacLyricsPane(container: container)
                case .queue:
                    MacQueuePane(isOnBackdrop: true)
                }
            }
        }
        // Compact, the window is exactly the controls' height; expanded, it can grow as tall as wanted.
        .frame(minWidth: MiniPlayerLayout.width, idealWidth: MiniPlayerLayout.width,
               minHeight: isExpanded ? MiniPlayerLayout.minimumExpandedHeight : MiniPlayerLayout.compactHeight,
               idealHeight: MiniPlayerLayout.height(expanded: isExpanded),
               maxHeight: isExpanded ? .infinity : MiniPlayerLayout.compactHeight)
        .environment(playback)
        .environment(interface.navigator)
        .tint(Color.minidiscAccent)
        .onAppear { MacSpaceKeyMonitor.shared.install(playback: playback) }
    }

    @ViewBuilder private func artwork(_ state: PlayerState) -> some View {
        if let track = state.currentTrack {
            CoverArtView(id: track.coverArtId ?? track.id, size: 240, cornerRadius: 6)
        } else if let radio = state.currentRadio {
            CoverArtView(id: radio.coverArt ?? radio.id, size: 240, cornerRadius: 6,
                         placeholderSystemImage: "dot.radiowaves.left.and.right")
        } else {
            MinidiscLogoView(isSpinning: false)
                .padding(8)
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

/// The playing song's heart in the MiniPlayer.
private struct MacMiniPlayerHeart: View {
    let track: DisplayableSong

    @Environment(MacPlayback.self) private var playback
    @Environment(\.minidiscPlayingAccent) private var accent

    var body: some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            Button {
                playback.setFavorite(toggle.toggled, songs: [track])
            } label: {
                Image(systemName: toggle.systemImage)
                    .foregroundStyle(toggle.isFavorite ? accent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(!playback.container.serverState.isOnline)
            .help(Text(toggle.actionTitle))
            .accessibilityLabel(Text("Favorite"))
            .accessibilityValue(Text(toggle.accessibilityValue))
            .accessibilityHint(Text(toggle.actionTitle))
            .accessibilityAddTraits(toggle.isFavorite ? .isSelected : [])
        }
    }
}
