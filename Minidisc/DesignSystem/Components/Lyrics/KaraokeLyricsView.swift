import SwiftSonic
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Full-screen lyrics: large centred lines over the blurred cover, following the song, with
/// tap-to-seek and play/pause. The screen stays awake while it is open.
struct KaraokeLyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    /// The player hands over a new view model when the song changes, which must be marked visible too.
    @State private var visibility = LyricsVisibilityHandoff()

    private var track: DisplayableSong? { container?.playerState.currentTrack }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loaded(let structured):
                lines(structured)
            default:
                Text("No lyrics available")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
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
                Color.black.opacity(0.35)
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
                            isSynced: structured.synced,
                            isTappable: structured.synced && line.start != nil,
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
            .onChange(of: viewModel.currentLineIndex, initial: true) { _, index in
                guard let index, !viewModel.isUserScrolling else { return }
                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { viewModel.userStartedScrolling() }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                                         .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? "").font(.headline).lineLimit(1)
                Text(track?.artist ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
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
