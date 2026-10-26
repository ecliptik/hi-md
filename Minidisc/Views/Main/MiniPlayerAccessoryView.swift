import SwiftUI
import SwiftSonic

struct MiniPlayerAccessoryView: View {
    var showingFullPlayer = false
    var artworkNamespace: Namespace.ID? = nil
    var initialArtwork: PlayerArtworkSnapshot? = nil
    var placementOverride: Bool? = nil
    var expandPlayer: () -> Void
    @Environment(\.appContainer) private var container
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(DominantColorExtractor.self) private var colorExtractor
    @State private var dragOffset: CGFloat = 0
    /// The playing cover's colour, darkened for white text; clear until it is known.
    @State private var coverTint: Color = .clear
    @State private var isAnimatingSwipe = false

    private let swipeThreshold: CGFloat = 100
    private let velocityThreshold: CGFloat = 200

    // Inherit the accessory’s system color scheme so text follows glass contrast changes.
    private var typoColor: Color { .primary }
    /// On the cover tint, the player's secondary white: the system secondary is 2.9:1 there.
    private var typoSecondaryColor: Color {
        coverTint != .clear ? .white.opacity(PlayerBackgroundPalette.secondaryOpacity) : .secondary
    }

    var body: some View {
        if let playerState = container?.playerState {
            MiniPlayerPlacementReader { isInline in
                playerContent(playerState, isInline: placementOverride ?? isInline)
            }
            // The system accessory has a fixed height. Larger text uses one metadata line;
            // keep its symbols within their 44-point controls while the full player scales freely.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    @ViewBuilder
    private func playerContent(_ playerState: PlayerState, isInline: Bool) -> some View {
        let isLiveStream = playerState.isLiveStream
        let coverArtId = isLiveStream ? (playerState.currentRadio?.coverArt ?? "") : (playerState.currentTrack?.coverArtId ?? playerState.currentTrack?.id ?? "")
        let title = isLiveStream ? (playerState.currentRadio?.name ?? "") : (playerState.currentTrack?.title ?? "")
        let artist: String? = isLiveStream ? "Live Radio" : playerState.currentTrack?.artist
        let isPlaying = playerState.wantsPlayback
        let isAvailable = playerState.isPlaybackAvailable

        Group {
            if isInline {
                inlineBar(coverArtId: coverArtId, title: title, artist: artist, isPlaying: isPlaying, isAvailable: isAvailable, isLiveStream: isLiveStream, status: playerState.playbackStatusMessage)
            } else {
                expandedBar(playerState: playerState, coverArtId: coverArtId, title: title, artist: artist, isPlaying: isPlaying, isAvailable: isAvailable, isLiveStream: isLiveStream, status: playerState.playbackStatusMessage)
            }
        }
        .task(id: coverArtId) { await loadCoverTint(coverArtId) }
        .offset(x: dragOffset)
        .opacity(1.0 - min(abs(dragOffset) / 200, 0.4))
        .contentShape(Rectangle())
        .onTapGesture(perform: expandPlayer)
        .gesture(!playerState.queue.isEmpty && !isLiveStream ? swipeSkipGesture : nil)
    }

    private func inlineBar(coverArtId: String, title: String, artist: String?, isPlaying: Bool, isAvailable: Bool, isLiveStream: Bool, status: String?) -> some View {
        HStack(spacing: MinidiscSpacing.m) {
            miniArtwork(coverArtId)
                .opacity(isAvailable ? 1.0 : 0.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .accessibilityIdentifier("player.mini.title")
                    .font(.minidiscCaption)
                    .fontWeight(.semibold)
                    .foregroundStyle(typoColor)
                    .lineLimit(1)
                    .accessibilityLabel(metadataLabel(title: title, artist: artist, status: status))
                if let status, !dynamicTypeSize.isAccessibilitySize {
                    Text(status)
                        .font(.minidiscCaption)
                        .foregroundStyle(typoSecondaryColor)
                        .lineLimit(1)
                } else if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: MinidiscSpacing.xs) {
                        if let artist {
                            Text(artist)
                                .font(.minidiscCaption)
                                .foregroundStyle(typoSecondaryColor)
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            playPauseButton(isPlaying: isPlaying, isAvailable: isAvailable)
        }
        .padding(.leading, MinidiscSpacing.m)
        .padding(.trailing, MinidiscSpacing.s)
        .padding(.vertical, MinidiscSpacing.s)
    }

    private func expandedBar(playerState: PlayerState, coverArtId: String, title: String, artist: String?, isPlaying: Bool, isAvailable: Bool, isLiveStream: Bool, status: String?) -> some View {
        // Avoid observing progress while the full player covers the accessory.
        let progress = showingFullPlayer || playerState.duration <= 0
            ? 0.0
            : playerState.position / playerState.duration
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: MinidiscSpacing.m) {
                miniArtwork(coverArtId, size: 40)
                    .opacity(isAvailable ? 1.0 : 0.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .accessibilityIdentifier("player.mini.title")
                        .font(.minidiscCellTitle.weight(.semibold))
                        .foregroundStyle(typoColor)
                        .lineLimit(1)
                        .accessibilityLabel(metadataLabel(title: title, artist: artist, status: status))
                    if let status, !dynamicTypeSize.isAccessibilitySize {
                        Text(status)
                            .font(.minidiscCaption)
                            .foregroundStyle(typoSecondaryColor)
                            .lineLimit(1)
                    } else if !dynamicTypeSize.isAccessibilitySize {
                        HStack(spacing: MinidiscSpacing.xs) {
                            if let artist {
                                Text(artist)
                                    .font(.minidiscCaption)
                                    .foregroundStyle(typoSecondaryColor)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: MinidiscSpacing.s) {
                    playPauseButton(isPlaying: isPlaying, isAvailable: isAvailable)
                    if !playerState.queue.isEmpty && !isLiveStream {
                        Button {
                            HapticFeedback.light.trigger()
                            Task { await container?.toastService.perform { try await container?.playerService.skipToNext() } }
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .foregroundStyle(typoColor)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Skip to next")
                    }
                }
                .frame(height: 36)
            }
            .padding(.leading, MinidiscSpacing.s)
            .padding(.trailing, MinidiscSpacing.s)
            .padding(.vertical, MinidiscSpacing.s)

            if isLiveStream {
                HStack(spacing: MinidiscSpacing.xs) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("LIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MinidiscSpacing.l)
                .frame(height: 3)
                .accessibilityHidden(true)
            } else {
                GeometryReader { geo in
                    Capsule()
                        // On the tint, the accent's text shade: the fill shade is 1.6:1 there.
                        .fill(isAvailable ? (coverTint != .clear ? Color.minidiscTextAccent : Color.minidiscAccent)
                                          : Color.secondary.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
        // A capsule tinted from the cover, fading a little towards the controls, with white text on
        // it. At 55% a light-mode glass behind the controls left them at 2.5:1; at 85% they keep 5:1.
        .background {
            if coverTint != .clear {
                LinearGradient(colors: [coverTint, coverTint.opacity(0.85)], startPoint: .leading, endPoint: .trailing)
            }
        }
        .environment(\.colorScheme, coverTint != .clear ? .dark : colorSchemeFallback)
    }

    @Environment(\.colorScheme) private var colorSchemeFallback

    private func loadCoverTint(_ coverArtId: String) async {
        guard !coverArtId.isEmpty else { coverTint = .clear; return }
        let color: Color
        if let cached = colorExtractor.cachedColor(for: coverArtId) {
            color = cached
        } else {
            guard let image = await container?.artworkImageCache.load(coverArtId: coverArtId) else { return }
            color = colorExtractor.dominantColor(for: coverArtId, image: image)
        }
        let tint = color == .clear ? .clear : Self.tint(for: color)
        withAnimation(.easeInOut(duration: 0.3)) { coverTint = tint }
    }

    /// The album screen's dark bottom colour, darkened like the full player's backdrop so white
    /// text reaches 4.5:1 at the player's secondary opacity.
    private static func tint(for dominantColor: Color) -> Color {
        PlayerBackgroundPalette.capped(
            AlbumDetailPalette(dominantColor: dominantColor, appearance: .dark).backgroundBottomColor)
    }

    private func miniArtwork(_ coverArtId: String, size: CGFloat = 30) -> some View {
        CoverArtView(id: coverArtId, size: 120,
                     initialImage: initialArtwork?.id == coverArtId ? initialArtwork?.image : nil)
            .minidiscCoverStyle()
            .modifier(PlayerArtworkTransition(namespace: artworkNamespace))
            .frame(width: size, height: size)
    }

    private func metadataLabel(title: String, artist: String?, status: String?) -> Text {
        let label = dynamicTypeSize.isAccessibilitySize
            ? [title, status ?? artist].compactMap { $0 }.joined(separator: ", ")
            : title
        return Text(verbatim: label)
    }

    private func playPauseButton(isPlaying: Bool, isAvailable: Bool) -> some View {
        Button {
            HapticFeedback.medium.trigger()
            Task {
                await container?.playerService.togglePlayPause()
            }
        } label: {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .foregroundStyle(typoColor)
                .opacity(isAvailable ? 1.0 : 0.3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isAvailable)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityIdentifier("player.mini.playPause")
    }

    private var swipeSkipGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isAnimatingSwipe else { return }
                let h = value.translation.width
                guard abs(h) > abs(value.translation.height) else { return }
                withAnimation(.interactiveSpring()) {
                    dragOffset = h
                }
            }
            .onEnded { value in
                guard !isAnimatingSwipe else { return }
                let h = value.translation.width
                let velocity = value.velocity.width
                guard abs(h) > abs(value.translation.height) else {
                    bounceback()
                    return
                }

                let triggeredNext = h < -swipeThreshold || velocity < -velocityThreshold
                let triggeredPrev = h > swipeThreshold || velocity > velocityThreshold

                if triggeredNext || triggeredPrev {
                    commitSwipe(goNext: triggeredNext)
                } else {
                    bounceback()
                }
            }
    }

    private func commitSwipe(goNext: Bool) {
        isAnimatingSwipe = true
        HapticFeedback.medium.trigger()

        let exitOffset: CGFloat = goNext ? -300 : 300
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = exitOffset
        }

        Task {
            if goNext {
                await container?.toastService.perform { try await container?.playerService.skipToNext() }
            } else {
                await container?.toastService.perform { try await container?.playerService.skipToPrevious() }
            }

            let entryOffset: CGFloat = goNext ? 300 : -300
            await MainActor.run {
                dragOffset = entryOffset
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    dragOffset = 0
                }
                isAnimatingSwipe = false
            }
        }
    }

    private func bounceback() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            dragOffset = 0
        }
    }
}

private struct MiniPlayerPlacementReader<Content: View>: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement: TabViewBottomAccessoryPlacement?
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(placement == .inline)
    }
}
