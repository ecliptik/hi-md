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

/// History, Playing Next, Related and the Lyrics toggle, in Plexamp's small capitals.
struct MiniPlayerTabBar: View {
    @Binding var panel: MiniPlayerPanelState
    let canShowLyrics: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            tab("Back To", .history)
            tab("Playing Next", .upNext)
            tab("Related", .related)
            Spacer(minLength: 0)
            lyricsTab
        }
        .font(.caption.weight(.bold))
        .textCase(.uppercase)
    }

    private func tab(_ title: LocalizedStringKey, _ tab: MiniPlayerTab) -> some View {
        let isSelected = panel.isSelected(tab, canShowLyrics: canShowLyrics)
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { panel.select(tab) }
        } label: {
            Text(title)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(NowPlayingText.secondaryOpacity))
                .background(isSelected ? Color.white.opacity(0.16) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isHeader] : .isHeader)
    }

    /// A toggle: on shows lyrics in the panel, off brings back the tab.
    private var lyricsTab: some View {
        let isOn = panel.isShowingLyrics(canShowLyrics: canShowLyrics)
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { panel.toggleLyrics() }
        } label: {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? Color.minidiscAccentText : Color.white.opacity(NowPlayingText.secondaryOpacity))
                .background(isOn ? Color.minidiscAccent : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canShowLyrics)
        .accessibilityLabel("Lyrics")
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .help("Lyrics")
    }
}

/// A song in the History and Related tabs.
struct MiniPlayerSongRow<Accessory: View>: View {
    let song: DisplayableSong
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            CoverArtView(id: song.coverArtId ?? song.id, size: 64, cornerRadius: 3)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.callout)
                    .foregroundStyle(.white)
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
        .contentShape(Rectangle())
    }
}

/// The songs before the current one, the most recent first. Clicking one goes back to it.
struct MiniPlayerHistoryList: View {
    @Environment(MacPlayback.self) private var playback

    var body: some View {
        let state = playback.state
        let history = QueueHistory.earlier(in: state.queue, currentIndex: state.currentIndex)
        if history.isEmpty {
            MiniPlayerEmptyTab(title: "No earlier songs", systemImage: "clock.arrow.circlepath")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(history) { entry in
                        Button {
                            guard let selection = QueueTrackSelection(playerState: state, destinationIndex: entry.index,
                                                                      destinationTrackID: entry.song.id) else { return }
                            playback.jump(to: selection)
                        } label: {
                            MiniPlayerSongRow(song: entry.song) {
                                Text(Duration.seconds(entry.song.duration).formatted(.time(pattern: .minuteSecond)))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Play")
                        .contextMenu { MacSongMenu(songs: [entry.song]) }
                    }
                }
                .padding(.horizontal, MiniPlayerLayout.inset)
            }
        }
    }
}

/// Songs like the one playing, each with Add to Queue and the usual song menu, and More for
/// another page.
struct MiniPlayerRelatedList: View {
    let model: MacMiniPlayerModel
    let container: AppContainer
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
                    .padding(.horizontal, MiniPlayerLayout.inset)
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
        }
        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
