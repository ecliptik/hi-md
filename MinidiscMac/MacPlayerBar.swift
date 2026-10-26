import SwiftSonic
import SwiftUI

/// The transport bar along the bottom of the window, laid out like the Music app's: the controls
/// on the left, the playing song with its scrubber in the middle, and volume and the inspector
/// buttons on the right.
struct MacPlayerBar: View {
    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator

    private var playerState: PlayerState { playback.state }

    var body: some View {
        let commands = playback.commands
        // Read here, not only inside the bindings, so the buttons redraw when the panel changes.
        let shownPane = navigator.inspector
        HStack(spacing: 18) {
            MacTransportControls(commands: commands)
                .frame(width: 210, alignment: .leading)
            MacNowPlayingDisplay()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            HStack(spacing: 14) {
                MacVolumeSlider()
                    .frame(width: 120)
                Toggle(isOn: inspectorBinding(.lyrics, shown: shownPane)) {
                    Label("Lyrics", systemImage: "quote.bubble")
                }
                .disabled(!commands.canShowLyrics && shownPane != .lyrics)
                .help("Lyrics")
                Toggle(isOn: inspectorBinding(.queue, shown: shownPane)) {
                    Label("Queue", systemImage: "list.bullet")
                }
                .help("Playing Next")
            }
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 210, alignment: .trailing)
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 64)
        .background(.bar)
    }

    private func inspectorBinding(_ pane: MacInspectorPane, shown: MacInspectorPane?) -> Binding<Bool> {
        Binding {
            shown == pane
        } set: { isOn in
            navigator.inspector = isOn ? pane : nil
        }
    }
}

/// Shuffle, Previous, Play/Pause, Next and Repeat.
struct MacTransportControls: View {
    let commands: PlaybackCommandState
    var showsModes = true
    /// The Now Playing view's bigger buttons.
    var isLarge = false

    @Environment(MacPlayback.self) private var playback
    @Environment(\.minidiscPlayingAccent) private var playingAccent

    var body: some View {
        let state = playback.state
        HStack(spacing: isLarge ? 32 : 16) {
            if showsModes {
                Button {
                    playback.toggleShuffle()
                } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(state.isShuffled ? playingAccent : .secondary)
                }
                .disabled(!commands.canShuffle)
                .accessibilityLabel("Shuffle")
                .accessibilityValue(state.isShuffled ? Text("On") : Text("Off"))
                .help("Shuffle")
            }

            Button(action: playback.skipToPrevious) {
                Image(systemName: "backward.fill")
            }
            .disabled(!commands.canSkip)
            .accessibilityLabel("Previous")
            .help("Previous")

            Button(action: playback.togglePlayPause) {
                Image(systemName: state.wantsPlayback ? "pause.fill" : "play.fill")
                    .font(isLarge ? .system(size: 40) : .title)
                    .frame(width: isLarge ? 48 : 28)
                    .contentTransition(.symbolEffect(.replace))
            }
            .disabled(!commands.canTogglePlayback)
            .accessibilityLabel(state.wantsPlayback ? "Pause" : "Play")
            .help(state.wantsPlayback ? "Pause" : "Play")

            Button(action: playback.skipToNext) {
                Image(systemName: "forward.fill")
            }
            .disabled(!commands.canSkip)
            .accessibilityLabel("Next")
            .help("Next")

            if showsModes {
                Button(action: playback.cycleRepeatMode) {
                    Image(systemName: state.repeatMode.systemImage)
                        .foregroundStyle(state.repeatMode == .off ? .secondary : playingAccent)
                }
                .disabled(!commands.canRepeat)
                .accessibilityLabel("Repeat")
                .accessibilityValue(Text(repeatValue(state.repeatMode)))
                .help("Repeat")
            }
        }
        .font(isLarge ? .title : .title3)
        .buttonStyle(.borderless)
    }

    private func repeatValue(_ mode: RepeatMode) -> LocalizedStringKey {
        switch mode {
        case .off: "Off"
        case .all: "All"
        case .one: "One"
        }
    }
}

/// The playing song's artwork, title and artist above the scrubber, like the Music app's display.
/// Clicking the title reveals the album; clicking the artist opens the artist.
private struct MacNowPlayingDisplay: View {
    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator

    var body: some View {
        let state = playback.state
        HStack(spacing: 10) {
            // The artwork opens the large Now Playing view, as the Music app's does.
            Button {
                navigator.showNowPlaying()
            } label: {
                Group {
                    if let radio = state.currentRadio {
                        CoverArtView(id: radio.coverArt ?? radio.id, size: 96, cornerRadius: 4, placeholderSystemImage: "dot.radiowaves.left.and.right")
                    } else if let track = state.currentTrack {
                        CoverArtView(id: track.coverArtId ?? track.id, size: 96, cornerRadius: 4)
                    } else {
                        MinidiscLogoView(isSpinning: false)
                            .padding(4)
                    }
                }
                .frame(width: 44, height: 44)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .padding(3)
                        .background(.regularMaterial, in: Circle())
                        .padding(2)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Now Playing")
            .accessibilityHint("Opens the large player with lyrics and the queue.")
            .help("Now Playing")

            VStack(spacing: 2) {
                if let radio = state.currentRadio {
                    Text(radio.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text("Live")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let track = state.currentTrack {
                    Button(track.title) { navigator.showAlbum(of: track, highlighting: true) }
                        .buttonStyle(.plain)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .disabled(track.albumId == nil || track.isLocalFile)
                        .help("Go to Album")
                    if let artist = track.artist {
                        Button(artist) { navigator.showArtist(of: track) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .disabled(track.artistId == nil || track.isLocalFile)
                    }
                } else {
                    Text("Not Playing")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                MacScrubber()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Elapsed time, the position slider and the time remaining. While dragging, the slider shows the
/// drag position and seeks once on release.
struct MacScrubber: View {
    /// The times' colour; secondary unless the Now Playing backdrop needs its own for contrast.
    var timeStyle: AnyShapeStyle = AnyShapeStyle(.secondary)

    @Environment(MacPlayback.self) private var playback
    @State private var dragPosition: TimeInterval?

    var body: some View {
        let state = playback.state
        let duration = state.duration > 0 ? state.duration : (state.currentTrack?.duration ?? 0)
        let shown = dragPosition ?? state.position
        HStack(spacing: 6) {
            Text(Duration.seconds(shown).formatted(.time(pattern: .minuteSecond)))
                .frame(width: 40, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { min(dragPosition ?? state.position, max(duration, 0)) },
                    set: { dragPosition = $0 }
                ),
                in: 0...max(duration, 1)
            ) { editing in
                guard !editing, let target = dragPosition else { return }
                Task {
                    await playback.seek(to: target)
                    dragPosition = nil
                }
            }
            .controlSize(.mini)
            .disabled(state.currentTrack == nil || state.isLiveStream || duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue(Duration.seconds(shown).formatted(.time(pattern: .minuteSecond)))
            Text(verbatim: "-\(Duration.seconds(max(duration - shown, 0)).formatted(.time(pattern: .minuteSecond)))")
                .frame(width: 44, alignment: .leading)
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(timeStyle)
    }
}

/// The app's volume, from silent to the system volume.
struct MacVolumeSlider: View {
    @Environment(MacPlayback.self) private var playback

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Slider(value: Binding(get: { Double(playback.volume) }, set: { playback.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .accessibilityLabel("Volume")
                .accessibilityValue(Text(playback.volume, format: .percent.precision(.fractionLength(0))))
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
                .imageScale(.small)
        }
    }
}
