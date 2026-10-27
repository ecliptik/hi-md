import SwiftUI
import SwiftSonic

struct LyricsView: View {
    @Bindable var viewModel: LyricsViewModel
    /// The player's secondary white: the system secondary is 2.9:1 on a saturated backdrop.
    private static let playerSecondary = Color.white.opacity(PlayerBackgroundPalette.secondaryOpacity)
    @State private var showsKaraoke = false
    @State private var visibility = LyricsVisibilityHandoff()
    @Environment(\.lyricsTypography) private var typography
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .minidiscFullScreenCover(isPresented: $showsKaraoke) { KaraokeLyricsView(viewModel: viewModel) }
    }

    // MARK: - Loaded

    /// The buttons sit in their own row above the lyrics rather than floating over them, and the
    /// lines fade out at the top edge, so a long line never runs under the buttons. Untimed
    /// lyrics read as plain text under a note instead of following the song.
    @ViewBuilder
    private func loadedContent(_ structured: StructuredLyrics) -> some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            Group {
                if structured.isTimed {
                    lyricsScroll(structured)
                } else {
                    untimedLyrics(structured)
                }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.topFade)
                    Color.black
                }
            }
        }
    }

    private static let topFade: CGFloat = 28

    /// Untimed lyrics at a reading size: 17 points on the iPhone, with Dynamic Type; on the Mac
    /// the size its pane sets, or 15 points.
    private func untimedLyrics(_ structured: StructuredLyrics) -> some View {
        #if os(iOS)
        let size = typography.plainSize ?? 17
        let scales = typography.plainSize == nil
        // The iPhone player fades the panel's bottom under its controls: the last stanza can
        // scroll clear of it.
        let bottom: CGFloat = 120
        #else
        let size = typography.plainSize ?? 15
        let scales = false
        let bottom: CGFloat = 32
        #endif
        let inset = typography.horizontalInset
        return UntimedLyricsView(
            lines: structured.line,
            note: viewModel.untimedNote,
            pointSize: size,
            scalesWithDynamicType: scales,
            usesSystemColors: typography.usesSystemColors,
            // Below the top fade, so the note starts fully visible.
            insets: EdgeInsets(top: Self.topFade + 4, leading: inset, bottom: bottom, trailing: inset)
        )
    }

    @ViewBuilder
    private func lyricsScroll(_ structured: StructuredLyrics) -> some View {
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
                .padding(.horizontal, typography.horizontalInset)
                .padding(.vertical, 200)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Open on the line being sung instead of scrolling down to it from the top, unless
                // Follow Lyrics is off: then the listener scrolls.
                viewModel.syncToPlayback()
                guard viewModel.autoScrollEnabled, let index = viewModel.currentLineIndex else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: viewModel.scrollRequest) { _, request in
                guard let request else { return }
                LyricsScrolling.scroll(proxy, to: request, reduceMotion: reduceMotion,
                                       animation: .easeInOut(duration: 0.3))
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
                    .foregroundStyle(headerStyle)
                }
            }

            Spacer()

            if typography.showsHeaderButtons {
                Button {
                    showsKaraoke = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Full Screen Lyrics")

                // Untimed lyrics don't follow the song, so there's nothing to follow.
                if viewModel.isTimed {
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
                    .accessibilityLabel("Follow Lyrics")
                    .accessibilityAddTraits(viewModel.autoScrollEnabled ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, typography.headerInset)
        .padding(.vertical, 12)
    }

    /// Without its buttons the header has nothing to show unless there's a language to pick, so
    /// the lines start at the top.
    private var showsHeader: Bool {
        typography.showsHeaderButtons || viewModel.availableLanguages.count > 1
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(secondary)
            Text("No lyrics available")
                .font(.minidiscDetailTitle)
                .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unsupportedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(secondary)
            Text("Lyrics not supported")
                .font(.minidiscDetailTitle)
                .foregroundStyle(secondary)
            Text("Update your Navidrome server to enable the songLyrics extension")
                .font(.callout)
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.octagon")
                .font(.system(size: 40))
                .foregroundStyle(secondary)
            Text("Failed to load lyrics")
                .font(.minidiscDetailTitle)
            Text(message)
                .font(.caption)
                .foregroundStyle(secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// The player's secondary white, or the system's secondary on the Mac main window's panel,
    /// which sits on the window's own background.
    private var secondary: AnyShapeStyle {
        typography.usesSystemColors ? AnyShapeStyle(.secondary) : AnyShapeStyle(Self.playerSecondary)
    }

    /// The header's language menu: the player's soft white, or the system's primary on the panel.
    private var headerStyle: AnyShapeStyle {
        typography.usesSystemColors ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white.opacity(0.8))
    }

    private func displayName(for lang: String) -> String {
        guard lang != "und", lang != "xxx" else { return "—" }
        return Locale.current.localizedString(forLanguageCode: lang)?.capitalized ?? lang.uppercased()
    }
}

/// Brings a lyrics view's line to the middle as its view model asks: gliding over a few lines,
/// straight there after a seek or a long scrub, and always straight there with Reduce Motion.
enum LyricsScrolling {
    static func scroll(_ proxy: ScrollViewProxy, to request: LyricsViewModel.ScrollRequest,
                       reduceMotion: Bool, animation: Animation) {
        if request.animated, !reduceMotion {
            withAnimation(animation) { proxy.scrollTo(request.index, anchor: .center) }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(request.index, anchor: .center) }
        }
    }
}
