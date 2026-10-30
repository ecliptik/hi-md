import SwiftSonic
import SwiftUI

/// Full-screen lyrics on the Mac, in two columns over a vivid gradient from the cover: on the
/// left the artwork, the song with its heart and menu, a thin scrubber and the transport; on the
/// right the lyrics, only about four huge lines, the one being sung held in the middle and the
/// others blurred and faded. Everything scales with the window (`FullScreenLyricsMetrics`).
/// Now Playing keeps its buttons over this view and hides them until the pointer moves; Escape
/// or the Lyrics button goes back.
struct MacFullScreenLyrics: View {
    let container: AppContainer
    let session: MacLyricsSession
    let backdropColors: [Color]
    @Binding var artworkMode: PlayerArtworkMode

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var state: PlayerState { playback.state }

    var body: some View {
        GeometryReader { proxy in
            let metrics = FullScreenLyricsMetrics(width: proxy.size.width, height: proxy.size.height)
            HStack(alignment: .center, spacing: metrics.columnGap) {
                playerColumn(metrics)
                    .frame(width: metrics.artworkSide)
                MacLyricsPane(container: container, session: session, isFullScreen: true)
                    .environment(\.lyricsTypography, .fullScreen(metrics))
                    .frame(width: metrics.lyricsWidth, height: metrics.lyricsHeight)
                    .background { wash(opacity: FullScreenLyricsBackdrop.lyricsWashOpacity, cornerRadius: metrics.lineSize) }
            }
            .padding(.horizontal, metrics.horizontalInset)
            .padding(.vertical, metrics.verticalInset)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background { backdrop.ignoresSafeArea() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full Screen Lyrics")
    }

    // MARK: Backdrop

    /// The cover's colours, vivid and bright, blended across the window. Reduce Transparency gets
    /// one solid colour, darkened as the lyrics' wash would, in place of the gradient and washes.
    @ViewBuilder private var backdrop: some View {
        let colors = FullScreenLyricsBackdrop.colors(from: backdropColors, accent: .minidiscAccent)
        if reduceTransparency {
            (colors.first ?? .black)
                .overlay(Color.black.opacity(FullScreenLyricsBackdrop.lyricsWashOpacity))
                .accessibilityHidden(true)
        } else {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.42, 0.55], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: Self.meshColors(colors),
                // Straight blends between the stops, which keeps every point under the cap.
                smoothsColors: false
            )
            .accessibilityHidden(true)
        }
    }

    /// Nine mesh points from the cover's bands, mixing them across the window.
    private static func meshColors(_ colors: [Color]) -> [Color] {
        guard !colors.isEmpty else { return Array(repeating: .black, count: 9) }
        return [0, 1, 2, 3, 2, 0, 1, 3, 2].map { colors[$0 % colors.count] }
    }

    /// A soft dark wash behind white text on the bright backdrop, feathered well outside the text
    /// so the text itself sits on its full opacity. None with Reduce Transparency, where the
    /// whole backdrop is darkened instead.
    @ViewBuilder private func wash(opacity: Double, cornerRadius: Double) -> some View {
        if !reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(opacity))
                .padding(-Self.washOutset)
                .blur(radius: Self.washOutset / 2)
                .accessibilityHidden(true)
        }
    }

    /// How far a wash reaches past its text; it fades over the outer half.
    private static let washOutset: Double = 48

    // MARK: Song and controls

    private func playerColumn(_ metrics: FullScreenLyricsMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.columnSpacing * 1.5) {
            // Clicking the artwork swaps it for the spinning MiniDisc, as in Now Playing.
            MacSpinningDiscArtwork(mode: $artworkMode, cornerRadius: 12 * metrics.scale, artworkSize: 1200)
                .frame(width: metrics.artworkSide, height: metrics.artworkSide)
                .shadow(color: .black.opacity(0.35), radius: 24 * metrics.scale, y: 12 * metrics.scale)
            VStack(spacing: metrics.columnSpacing) {
                songInfo(metrics)
                MacScrubber(timeStyle: AnyShapeStyle(.white.opacity(NowPlayingText.secondaryOpacity)),
                            timeFont: .system(size: metrics.timeSize, weight: .semibold),
                            timeWidth: metrics.timeSize * 3.8)
                MacTransportControls(commands: playback.commands, isLarge: true,
                                     largeGlyphSize: metrics.transportSize, largePlaySize: metrics.playSize)
                    .foregroundStyle(.white)
            }
            .background { wash(opacity: FullScreenLyricsBackdrop.textWashOpacity, cornerRadius: 24) }
        }
    }

    /// The title on one line with the small heart and menu at its right, and "Artist — Album" on
    /// one line under it, across the whole column; the album truncates before the artist.
    private func songInfo(_ metrics: FullScreenLyricsMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: 8) {
                Text(state.currentTrack?.title ?? state.currentRadio?.name ?? String(localized: "Not Playing"))
                    .font(.system(size: metrics.titleSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let track = state.currentTrack, !track.isLocalFile {
                    MacSongButtons(track: track, buttonSide: metrics.songButtonSize)
                }
            }
            if let track = state.currentTrack {
                MacSongSubtitle(artist: track.artist, album: track.albumName)
                    .font(.system(size: metrics.subtitleSize))
                    .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// "Artist — Album" on one line, the album truncating first so the artist stays readable.
struct MacSongSubtitle: View {
    let artist: String?
    let album: String?

    var body: some View {
        let parts = NowPlayingText.subtitleParts(artist: artist, album: album)
        HStack(spacing: 0) {
            if let artist = parts.artist {
                Text(verbatim: artist)
                    .layoutPriority(1)
            }
            if parts.artist != nil, parts.album != nil {
                Text(verbatim: " — ")
                    .layoutPriority(1)
                    .accessibilityHidden(true)
            }
            if let album = parts.album {
                Text(verbatim: album)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityElement(children: .combine)
    }
}

/// The full-screen lines: left-aligned, the one being sung held in the middle of a window about
/// four lines tall, the others blurred and faded the further they are. Clicking a line plays from
/// it. A scrub or seek lands straight on its line; playback glides from line to line. Untimed
/// lyrics read as plain text under a note instead, scrolled freely.
struct MacFullScreenLyricsLines: View {
    @Bindable var viewModel: LyricsViewModel

    @Environment(\.lyricsTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibility = LyricsVisibilityHandoff()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loaded(let structured) where structured.isTimed:
                lines(structured)
            case .loaded(let structured):
                untimedLines(structured)
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Text("No lyrics available")
                    .font(.system(size: (typography.lineSize ?? 40) * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(PlayerBackgroundPalette.secondaryOpacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: ObjectIdentifier(viewModel), initial: true) { visibility.show(viewModel) }
        .onChange(of: viewModel.isPlaying) { viewModel.reconcileTracking() }
        .onDisappear { visibility.hide() }
    }

    private func lines(_ structured: StructuredLyrics) -> some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: typography.lineSpacing) {
                        ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                            LyricsLineView(
                                value: line.value,
                                index: index,
                                currentIndex: viewModel.currentLineIndex,
                                isSynced: true,
                                isTappable: line.start != nil,
                                onTap: { viewModel.userTapped(lineIndex: index) }
                            )
                            .id(index)
                        }
                    }
                    // Room above the first line and below the last, so either can sit in the middle.
                    .padding(.vertical, geometry.size.height / 2)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    viewModel.syncToPlayback()
                    guard viewModel.autoScrollEnabled, let index = viewModel.currentLineIndex else { return }
                    LyricsScrolling.scroll(proxy, to: .init(index: index, animated: false, revision: 0),
                                           reduceMotion: reduceMotion, animation: Self.glide)
                }
                .onChange(of: viewModel.scrollRequest) { _, request in
                    guard let request else { return }
                    LyricsScrolling.scroll(proxy, to: request, reduceMotion: reduceMotion, animation: Self.glide)
                }
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .interacting:
                        viewModel.userStartedScrolling()
                    case .decelerating, .idle:
                        if viewModel.isUserScrolling { viewModel.userStoppedScrolling() }
                    default:
                        break
                    }
                }
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                             .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            }
        }
    }

    /// Regular left-aligned text at 24 to 30 points (`FullScreenLyricsMetrics.plainLineSize`),
    /// every line alike, over the lyrics' wash, fading only at the very edges.
    private func untimedLines(_ structured: StructuredLyrics) -> some View {
        let size = typography.plainSize ?? 26
        return UntimedLyricsView(
            lines: structured.line,
            note: viewModel.untimedNote,
            pointSize: size,
            scalesWithDynamicType: false,
            insets: EdgeInsets(top: Self.untimedFade + 4, leading: 0, bottom: Self.untimedFade + 4, trailing: 0)
        )
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.untimedFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.untimedFade)
            }
        }
    }

    private static let untimedFade: CGFloat = 24

    /// The current line easing into the middle.
    private static let glide: Animation = .smooth(duration: 0.5)
}
