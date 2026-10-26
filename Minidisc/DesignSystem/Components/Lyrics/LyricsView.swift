import SwiftUI
import SwiftSonic

struct LyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    /// The player's secondary white: the system secondary is 2.9:1 on a saturated backdrop.
    private static let secondary = Color.white.opacity(PlayerBackgroundPalette.secondaryOpacity)
    @State private var showsKaraoke = false
    @State private var visibility = LyricsVisibilityHandoff()

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded(let structured):
                loadedContent(structured)

            case .empty:
                emptyState

            case .unsupported:
                unsupportedState

            case .error(let message):
                errorState(message)
            }
        }
        .onAppear { visibility.show(viewModel) }
        // The player swaps in the next song's view model while this view stays on screen.
        .onChange(of: ObjectIdentifier(viewModel)) { visibility.show(viewModel) }
        .onDisappear { visibility.hide() }
        .onChange(of: viewModel.isPlaying) { _, _ in viewModel.reconcileTracking() }
        .fullScreenCover(isPresented: $showsKaraoke) { KaraokeLyricsView(viewModel: viewModel) }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(_ structured: StructuredLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 32) {
                    ForEach(Array(structured.line.enumerated()), id: \.offset) { index, line in
                        LyricsLineView(
                            value: line.value,
                            index: index,
                            currentIndex: viewModel.currentLineIndex,
                            isSynced: structured.synced,
                            isTappable: structured.synced && line.start != nil,
                            onTap: { viewModel.userTapped(lineIndex: index) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 200)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Open on the line being sung instead of scrolling down to it from the top.
                viewModel.syncToPlayback()
                guard let index = viewModel.currentLineIndex else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard viewModel.autoScrollEnabled,
                      !viewModel.isUserScrolling,
                      let newIndex else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onScrollPhaseChange { _, newPhase in
                switch newPhase {
                case .interacting:
                    viewModel.userStartedScrolling()
                case .decelerating, .idle:
                    guard viewModel.isUserScrolling else { return }
                    viewModel.userStoppedScrolling()
                default:
                    break
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 16) {
            if viewModel.availableLanguages.count > 1 {
                Menu {
                    ForEach(viewModel.availableLanguages, id: \.self) { lang in
                        Button(displayName(for: lang)) {
                            viewModel.selectLanguage(lang)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(displayName(for: viewModel.selectedLanguage ?? "und"))
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer()

            Button {
                showsKaraoke = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Full Screen Lyrics")

            Button {
                viewModel.autoScrollEnabled.toggle()
            } label: {
                Image(systemName: viewModel.autoScrollEnabled
                    ? "arrow.up.arrow.down.circle.fill"
                    : "arrow.up.arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Self.secondary)
            Text("No lyrics available")
                .font(.minidiscDetailTitle)
                .foregroundStyle(Self.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(Self.secondary)
            Text("Lyrics not supported")
                .font(.minidiscDetailTitle)
                .foregroundStyle(Self.secondary)
            Text("Update your Navidrome server to enable the songLyrics extension")
                .font(.callout)
                .foregroundStyle(Self.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 40))
                .foregroundStyle(Self.secondary)
            Text("Failed to load lyrics")
                .font(.minidiscDetailTitle)
            Text(message)
                .font(.caption)
                .foregroundStyle(Self.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func displayName(for lang: String) -> String {
        guard lang != "und", lang != "xxx" else { return "—" }
        return Locale.current.localizedString(forLanguageCode: lang)?.capitalized ?? lang.uppercased()
    }
}
