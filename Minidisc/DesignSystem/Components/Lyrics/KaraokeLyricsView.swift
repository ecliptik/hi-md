import SwiftSonic
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Full-screen lyrics: large centred lines over the blurred cover, following the song, with
/// tap-to-seek and play/pause. Untimed lyrics read as calm plain text under a note instead.
/// The screen stays awake while it is open.
struct KaraokeLyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The player hands over a new view model when the song changes, which must be marked visible too.
    @State private var visibility = LyricsVisibilityHandoff()

    private var track: DisplayableSong? { container?.playerState.currentTrack }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loaded(let structured) where structured.isTimed:
                lines(structured)
            case .loaded(let structured):
                untimedLines(structured)
            default:
                Text("No lyrics available")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(PlayerBackgroundPalette.secondaryOpacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A background never affects layout, so the filled cover can't widen the screen.
        .background { background }
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottom) { playPause }
        .preferredColorScheme(.dark)
        #if os(iOS)
        .statusBarHidden()
        #endif
        .onChange(of: ObjectIdentifier(viewModel), initial: true) { visibility.show(viewModel) }
        .onChange(of: viewModel.isPlaying) { viewModel.reconcileTracking() }
        .onAppear { setIdleTimerDisabled(true) }
        .onDisappear {
            visibility.hide()
            setIdleTimerDisabled(false)
        }
    }

    /// Keeps an iPhone or iPad awake while the lyrics are open; the Mac manages its own display sleep.
    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    private var background: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                if let track {
                    CoverArtView(id: track.coverArtId ?? track.id, size: 600)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .blur(radius: 60)
                        .opacity(0.55)
                }
                // Keeps a white cover at luminance 0.074 or less, so the dimmest lyric line
                // (0.5) still has 3.5:1.
                Color.black.opacity(0.45)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func lines(_ structured: StructuredLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 40) {
                    ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                        LyricsLineView(
                            value: line.value,
                            index: index,
                            currentIndex: viewModel.currentLineIndex,
                            isSynced: true,
                            isTappable: line.start != nil,
                            onTap: { viewModel.userTapped(lineIndex: index) },
                            isKaraoke: true
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 320)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                viewModel.syncToPlayback()
                guard let index = viewModel.currentLineIndex else { return }
                LyricsScrolling.scroll(proxy, to: .init(index: index, animated: false, revision: 0),
                                       reduceMotion: reduceMotion, animation: .easeInOut(duration: 0.35))
            }
            // A scrub or seek lands straight on its line; playback glides line to line.
            .onChange(of: viewModel.scrollRequest) { _, request in
                guard let request else { return }
                LyricsScrolling.scroll(proxy, to: request, reduceMotion: reduceMotion,
                                       animation: .easeInOut(duration: 0.35))
            }
            // Full screen follows the song even with Follow Lyrics off in the player.
            .onChange(of: viewModel.currentLineIndex) { previous, index in
                guard let index, !viewModel.autoScrollEnabled, !viewModel.isUserScrolling else { return }
                LyricsScrolling.scroll(proxy, to: .init(index: index, animated: LyricsScrollPolicy.animates(from: previous, to: index),
                                                        revision: 0),
                                       reduceMotion: reduceMotion, animation: .easeInOut(duration: 0.35))
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { viewModel.userStartedScrolling() }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }

    /// Untimed lyrics: regular left-aligned text at a reading size (title 2, with Dynamic Type),
    /// scrolled freely between the header and the play button, which it fades out under.
    private func untimedLines(_ structured: StructuredLyrics) -> some View {
        UntimedLyricsView(
            lines: structured.line,
            note: viewModel.untimedNote,
            pointSize: 22,
            textStyle: .title2,
            scalesWithDynamicType: true,
            insets: EdgeInsets(top: Self.untimedTopFade + 8, leading: 28, bottom: Self.untimedBottomFade + 8, trailing: 28)
        )
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.untimedTopFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.untimedBottomFade)
            }
        }
    }

    /// Clear of the song's title and the close button above, and the play button below.
    private static let untimedTopFade: CGFloat = 88
    private static let untimedBottomFade: CGFloat = 104

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "").font(.headline).lineLimit(1)
                Text(track?.artist ?? "").font(.subheadline)
                    .foregroundStyle(.white.opacity(PlayerBackgroundPalette.secondaryOpacity)).lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var playPause: some View {
        Button {
            HapticFeedback.medium.trigger()
            Task { await container?.playerService.togglePlayPause() }
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
        .padding(.bottom, 24)
    }
}
