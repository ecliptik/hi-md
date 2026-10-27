import SwiftSonic
import SwiftUI

/// The MiniPlayer as a bar (`MiniPlayerLayout.bar`): a short strip on the cover's colours with,
/// from the left, a small thumbnail, the song over a thin waveform scrubber, the transport, the
/// heart, the ⋯ menu and the expand button that goes back to the artwork. Unlike the controls
/// over the artwork it's always showing, as it's too small to hide anything; only the traffic
/// lights follow the idle rule, and the bar starts to their right so nothing sits under them. As
/// the window narrows the ⋯ menu goes first, then the heart, then the times
/// (`MiniPlayerBarItems`). The thumbnail is only a picture: the disc toggles from the big artwork.
struct MacMiniPlayerBar<Menu: View>: View {
    let waveform: WaveformEnvelope?
    /// Room on the left for the traffic lights.
    let leadingInset: Double
    var focus: FocusState<MiniPlayerControl?>.Binding
    let expand: () -> Void
    @ViewBuilder var menu: () -> Menu

    @Environment(MacPlayback.self) private var playback

    static var thumbnailSide: Double { 48 }

    var body: some View {
        let state = playback.state
        GeometryReader { proxy in
            let items = MiniPlayerBarItems(width: Double(proxy.size.width))
            HStack(spacing: 0) {
                thumbnail(state)
                    .padding(.leading, leadingInset)
                songColumn(state, showsTimes: items.showsTimes)
                    .padding(.horizontal, 10)
                transport(state)
                trailingButtons(state, items: items)
                    .padding(.leading, 8)
            }
            .padding(.trailing, 12)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: MiniPlayerLayout.barHeight)
    }

    // MARK: Parts

    @ViewBuilder private func thumbnail(_ state: PlayerState) -> some View {
        Group {
            if let radio = state.currentRadio {
                CoverArtView(id: radio.coverArt ?? radio.id, size: 128, cornerRadius: 6,
                             placeholderSystemImage: "dot.radiowaves.left.and.right", crossfades: true)
            } else if let track = state.currentTrack {
                // A song without a cover shows the disc, turning while it plays, as the artwork does.
                CoverArtView(id: track.coverArtId ?? track.id, size: 128, cornerRadius: 6,
                             spinningDisc: state.playbackState == .playing, crossfades: true)
            } else {
                MinidiscLogoView(isSpinning: false)
            }
        }
        .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // Only a picture: the song's title is read from the text beside it.
        .accessibilityHidden(true)
    }

    /// The title in bold above "Artist — Album", one line each, over the thin scrubber.
    private func songColumn(_ state: PlayerState, showsTimes: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            VStack(alignment: .leading, spacing: 1) {
                if let track = state.currentTrack {
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
                } else {
                    Text("Not Playing")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(NowPlayingText.secondaryOpacity))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
            // A plain thin bar until the song's waveform is measured, then the waveform at a
            // height that fits the strip.
            MacWaveformScrubber(envelope: waveform, height: 12, showsTimes: showsTimes, showsRemaining: true,
                                timeFont: .caption2.weight(.bold), timeWidth: 30)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Previous, Play/Pause and Next in white, as over the artwork.
    private func transport(_ state: PlayerState) -> some View {
        let commands = playback.commands
        return HStack(spacing: 2) {
            transportButton("Previous", systemImage: "backward.fill", size: 16, control: .previous,
                            action: playback.skipToPrevious)
                .disabled(!commands.canSkip)
            transportButton(state.wantsPlayback ? "Pause" : "Play",
                            systemImage: state.wantsPlayback ? "pause.fill" : "play.fill",
                            size: 22, control: .playPause, action: playback.togglePlayPause)
                .disabled(!commands.canTogglePlayback)
            transportButton("Next", systemImage: "forward.fill", size: 16, control: .next, action: playback.skipToNext)
                .disabled(!commands.canSkip)
        }
        .buttonStyle(.plain)
    }

    private func transportButton(_ title: LocalizedStringKey, systemImage: String, size: Double,
                                 control: MiniPlayerControl, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: max(size * 1.55, 30), height: 32)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .focused(focus, equals: control)
        .accessibilityLabel(Text(title))
        .help(Text(title))
    }

    /// The heart and the ⋯ menu while there's room, and the expand button always.
    private func trailingButtons(_ state: PlayerState, items: MiniPlayerBarItems) -> some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                if items.showsHeart, let track = state.currentTrack, !track.isLocalFile {
                    MacMiniPlayerHeart(track: track)
                        .focused(focus, equals: .favorite)
                }
                if items.showsMenu {
                    menu()
                }
                Button(action: expand) {
                    MacGlassCircleLabel(systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .focused(focus, equals: .expand)
                .accessibilityLabel("Expand MiniPlayer")
                .help("Expand MiniPlayer")
            }
        }
    }
}
