import SwiftSonic
import SwiftUI

/// The player along the bottom of the window, a floating Liquid Glass capsule like the Music
/// app's: the controls on the left, the playing song with its artwork and scrubber in the middle,
/// and volume and the lyrics and queue toggles on the right, the one open filled with the accent.
/// The root view gives it its own row along the window's bottom, so pages stop above it and no
/// AppKit-backed table can draw over it.
struct MacPlayerBar: View {
    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var paneSelection

    /// The capsule's height, its widest, and the margin it floats at from the content's edges.
    static let height: Double = 56
    static let maxWidth: Double = 860
    static let margin: Double = 10

    private var playerState: PlayerState { playback.state }

    var body: some View {
        let commands = playback.commands
        // Read here, not only inside the bindings, so the buttons redraw when the panel changes.
        let shownPane = navigator.inspector
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // The window's text colour, not the accent: gold glyphs vanish over yellow covers.
                // Shuffle and repeat still turn gold when on.
                MacTransportControls(commands: commands)
                    .tint(.primary)
                    .frame(width: 180, alignment: .leading)
                MacNowPlayingDisplay()
                    .frame(maxWidth: .infinity)
                HStack(spacing: 10) {
                    MacVolumeSlider()
                        .frame(width: 96)
                    HStack(spacing: 2) {
                        MacGlassSegment(title: "Lyrics", systemImage: "quote.bubble", isOn: shownPane == .lyrics,
                                        side: 28, selection: paneSelection) {
                            toggle(.lyrics, shown: shownPane)
                        }
                        .disabled(!commands.canShowLyrics && shownPane != .lyrics)
                        MacGlassSegment(title: "Playing Next", systemImage: "list.bullet", isOn: shownPane == .queue,
                                        side: 28, selection: paneSelection) {
                            toggle(.queue, shown: shownPane)
                        }
                    }
                }
                .frame(width: 180, alignment: .trailing)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .frame(height: Self.height)
            // A layer of the window's background under the content keeps the controls legible
            // over bright covers scrolling beneath; the glass still shows through at the edges.
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.62), in: Capsule())
            .macGlass(in: Capsule(), interactive: false)
            .frame(maxWidth: Self.maxWidth)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Self.margin * 2)
        .padding(.bottom, Self.margin)
    }

    private func toggle(_ pane: MacInspectorPane, shown: MacInspectorPane?) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            navigator.inspector = shown == pane ? nil : pane
        }
    }

}

/// Shuffle, Previous, Play/Pause, Next and Repeat.
struct MacTransportControls: View {
    let commands: PlaybackCommandState
    var showsModes = true
    /// The Now Playing view's bigger buttons.
    var isLarge = false
    /// The Now Playing view's glyph and play-button sizes, which grow with the window.
    var largeGlyphSize: Double = 22
    var largePlaySize: Double = 40

    @Environment(MacPlayback.self) private var playback
    @Environment(\.minidiscPlayingAccent) private var playingAccent

    var body: some View {
        let state = playback.state
        HStack(spacing: isLarge ? largeGlyphSize * 1.4 : 16) {
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
                    .font(isLarge ? .system(size: largePlaySize) : .title)
                    .frame(width: isLarge ? largePlaySize * 1.2 : 28)
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
        .font(isLarge ? .system(size: largeGlyphSize) : .title3)
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
/// Clicking the title reveals the album; clicking the artist opens the artist; the heart at the
/// end of the title line stars the song.
private struct MacNowPlayingDisplay: View {
    @Environment(MacPlayback.self) private var playback
    @Environment(MacNavigator.self) private var navigator
    @Environment(\.minidiscPlayingAccent) private var accent

    var body: some View {
        let state = playback.state
        HStack(spacing: 10) {
            // The artwork opens the large Now Playing view, as the Music app's does.
            Button {
                navigator.showNowPlaying()
            } label: {
                Group {
                    if let radio = state.currentRadio {
                        CoverArtView(id: radio.coverArt ?? radio.id, size: 96, cornerRadius: 9,
                                     placeholderSystemImage: "dot.radiowaves.left.and.right", crossfades: true)
                    } else if let track = state.currentTrack {
                        // The next song's cover fades in over this one once it's ready.
                        CoverArtView(id: track.coverArtId ?? track.id, size: 96, cornerRadius: 9, crossfades: true)
                    } else {
                        MinidiscLogoView(isSpinning: false)
                            .padding(4)
                    }
                }
                .frame(width: 42, height: 42)
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

            VStack(spacing: 1) {
                if let radio = state.currentRadio {
                    Text(radio.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text("Live")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let track = state.currentTrack {
                    Button(track.title) { navigator.showAlbum(of: track, highlighting: true) }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 26)
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                MacScrubber()
            }
            // Room at either end of the title line, so a long title never runs under the heart.
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if state.currentRadio == nil, let track = state.currentTrack, !track.isLocalFile {
                    heart(for: track)
                }
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        // The centre segment, a shade inside the glass, as the Music app's.
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The same store as every other heart, so it changes with them, offline too.
    private func heart(for track: DisplayableSong) -> some View {
        FavoriteMatches(.song, id: track.id) { toggle in
            Button {
                playback.setFavorite(toggle.toggled, itemType: .song, id: track.id)
            } label: {
                Image(systemName: toggle.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(toggle.isFavorite ? accent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(toggle.actionTitle))
            .accessibilityLabel(Text("Favorite"))
            .accessibilityValue(Text(toggle.accessibilityValue))
            .accessibilityAddTraits(toggle.isFavorite ? .isSelected : [])
        }
        .padding(.top, 1)
    }
}

/// Elapsed time, the position slider and the time remaining. While dragging, the slider shows the
/// drag position and seeks once on release.
struct MacScrubber: View {
    /// The times' colour; secondary unless the Now Playing backdrop needs its own for contrast.
    var timeStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    var timeFont: Font = .caption2
    /// Room for "00:00", so the slider doesn't move as the time changes.
    var timeWidth: Double = 40

    @Environment(MacPlayback.self) private var playback
    @State private var dragPosition: TimeInterval?
    @State private var isEditing = false
    @State private var keyboardSeek: Task<Void, Never>?

    var body: some View {
        let state = playback.state
        let duration = state.duration > 0 ? state.duration : (state.currentTrack?.duration ?? 0)
        let shown = dragPosition ?? state.position
        HStack(spacing: 6) {
            Text(Duration.seconds(shown).formatted(.time(pattern: .minuteSecond)))
                .frame(width: timeWidth, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { min(dragPosition ?? state.position, max(duration, 0)) },
                    set: { newValue in
                        dragPosition = newValue
                        // The lyrics follow the drag before the seek.
                        playback.scrub(to: newValue)
                        if !isEditing {
                            // The arrow keys or VoiceOver: no drag to wait for, so seek once the
                            // presses pause, unless a drag starts first.
                            keyboardSeek?.cancel()
                            keyboardSeek = Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled, !isEditing else { return }
                                await playback.seek(to: newValue)
                                if !isEditing { dragPosition = nil }
                            }
                        }
                    }
                ),
                in: 0...max(duration, 1)
            ) { editing in
                isEditing = editing
                guard !editing else {
                    keyboardSeek?.cancel()
                    return
                }
                guard let target = dragPosition else {
                    playback.cancelScrub()
                    return
                }
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
                .frame(width: timeWidth * 1.1, alignment: .leading)
        }
        .font(timeFont)
        .monospacedDigit()
        .foregroundStyle(timeStyle)
        .onDisappear {
            keyboardSeek?.cancel()
            if isEditing || dragPosition != nil { playback.cancelScrub() }
        }
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
