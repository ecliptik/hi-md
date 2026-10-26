import SwiftSonic
import SwiftUI

/// Full-screen lyrics on the Mac: they take over the whole Now Playing window rather than the
/// iPhone's phone-shaped karaoke sheet. Huge centred lines over the blurred, tinted cover, the
/// song in a small header, and a slim control bar that shows while the pointer moves. Escape,
/// the close button or the full-screen button again go back to Now Playing.
struct MacFullScreenLyrics: View {
    let container: AppContainer
    let session: MacLyricsSession
    let backdropColors: [Color]
    let close: () -> Void

    @Environment(MacPlayback.self) private var playback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var showsControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    private var track: DisplayableSong? { playback.state.currentTrack }

    var body: some View {
        GeometryReader { proxy in
            MacLyricsPane(container: container, session: session, isFullScreen: true)
                .environment(\.lyricsTypography, .karaoke(forWidth: proxy.size.width))
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background { background.ignoresSafeArea() }
        .overlay(alignment: .topLeading) { header }
        .overlay(alignment: .topTrailing) { closeButton }
        .overlay(alignment: .bottom) { controlBar }
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        .onAppear { revealControls() }
        .onDisappear { hideControlsTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Full Screen Lyrics")
    }

    // MARK: Backdrop

    /// The cover filling the window, blurred and darkened by the player's palette so the dimmest
    /// line keeps 3:1. Reduce Transparency gets the palette's solid colour instead.
    @ViewBuilder private var background: some View {
        let colors = PlayerBackgroundPalette.colors(from: backdropColors)
        if reduceTransparency {
            (colors.first ?? .black)
        } else {
            GeometryReader { proxy in
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let track {
                        CoverArtView(id: track.coverArtId ?? track.id, size: 600)
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .blur(radius: 80)
                            .opacity(0.45)
                    }
                    // Keeps a white cover at luminance 0.074 or less, as the iPhone's karaoke does.
                    Color.black.opacity(0.45)
                }
            }
            .accessibilityHidden(true)
        }
    }

    // MARK: Header and controls

    /// Clear of the traffic lights, which sit over the top-left corner.
    private var header: some View {
        HStack(spacing: 12) {
            if let track {
                CoverArtView(id: track.coverArtId ?? track.id, size: 120, cornerRadius: 6)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.headline)
                    if let artist = track.artist {
                        Text(artist)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(NowPlayingText.secondaryOpacity))
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.leading, 28)
        .padding(.top, 44)
        .accessibilityElement(children: .combine)
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.body.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(reduceTransparency ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(.ultraThinMaterial),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit Full Screen Lyrics")
        .help("Exit Full Screen Lyrics")
        .padding(.trailing, 24)
        .padding(.top, 44)
    }

    /// The scrubber and transport, shown while the pointer moves and for a few seconds after;
    /// always with VoiceOver.
    private var controlBar: some View {
        let visible = showsControls || voiceOverEnabled
        return VStack(spacing: 8) {
            MacScrubber(timeStyle: AnyShapeStyle(.white.opacity(NowPlayingText.secondaryOpacity)))
            MacTransportControls(commands: playback.commands, showsModes: false)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 520)
        .background(reduceTransparency ? AnyShapeStyle(Color.black.opacity(0.55)) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.bottom, 28)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visible)
    }

    private func revealControls() {
        showsControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showsControls = false
        }
    }
}

/// The full-screen lines: centred, scrolling to the line being sung, with the iPhone karaoke
/// view's depth of field. Clicking a line seeks to it.
struct MacFullScreenLyricsLines: View {
    @Bindable var viewModel: LyricsViewModel

    @Environment(\.lyricsTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibility = LyricsVisibilityHandoff()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loaded(let structured):
                lines(structured)
            case .loading:
                ProgressView()
            default:
                Text("No lyrics available")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white.opacity(PlayerBackgroundPalette.secondaryOpacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: ObjectIdentifier(viewModel), initial: true) { visibility.show(viewModel) }
        .onChange(of: viewModel.isPlaying) { viewModel.reconcileTracking() }
        .onDisappear { visibility.hide() }
    }

    private func lines(_ structured: StructuredLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: typography.lineSpacing) {
                    ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                        LyricsLineView(
                            value: line.value,
                            index: index,
                            currentIndex: viewModel.currentLineIndex,
                            isSynced: structured.synced,
                            isTappable: structured.synced && line.start != nil,
                            onTap: { viewModel.userTapped(lineIndex: index) },
                            isKaraoke: true
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, typography.horizontalInset)
                .padding(.vertical, 360)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                viewModel.syncToPlayback()
                guard let index = viewModel.currentLineIndex else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(index, anchor: .center) }
            }
            .onChange(of: viewModel.currentLineIndex) { _, index in
                guard let index, viewModel.autoScrollEnabled, !viewModel.isUserScrolling else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) }
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
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }
}
