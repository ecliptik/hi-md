import SwiftUI

// ArtworkImageCache's storage is not observed, so a read in a view body is a snapshot
// that never updates when the cover arrives. The body reads it once so a RAM hit renders
// on the first pass; everything else resolves from a task.
/// Resolves cover art through the shared cache, then falls back to AsyncImage.
/// Sizes of at least 480 points use the hero tier unless `tier` overrides it.
///
/// While a cover loads it shows a neutral tile. Once the cover is known to be missing (no id, or
/// the cache recorded that it can't be loaded; see `CoverArtPhase`) albums, songs and playlists
/// show the MiniDisc, and artists and stations their placeholder symbol.
struct CoverArtView: View {
    let id: String
    let size: Int?
    var tier: ArtworkTier? = nil
    var cornerRadius: CGFloat = 0
    var placeholderSystemImage: String = CoverArtPlaceholder.defaultSymbol
    var initialImage: PlatformImage? = nil
    /// Defers loading for mounted rows that are not yet visible.
    var loadingEnabled: Bool = true
    /// For the one large cover of the current song (Now Playing, the MiniPlayer, full-screen
    /// lyrics): a missing cover shows the logo on its own, turning while this is true, instead of
    /// the still disc on a tile.
    var spinningDisc: Bool? = nil

    /// A cover that arrives from disk or the server fades in over the placeholder, so a screen
    /// filling on a cold launch doesn't flash. RAM hits render on the first pass and never animate.
    static let arrival: Animation = .easeOut(duration: 0.25)

    var body: some View {
        CoverArtViewContent(
            id: id,
            size: size,
            tier: tier,
            cornerRadius: cornerRadius,
            placeholderSystemImage: placeholderSystemImage,
            initialImage: initialImage,
            loadingEnabled: loadingEnabled,
            spinningDisc: spinningDisc
        )
    }
}

// MARK: - Content

private struct CoverArtViewContent: View {
    let id: String
    let size: Int?
    let tier: ArtworkTier?
    let cornerRadius: CGFloat
    let placeholderSystemImage: String
    let loadingEnabled: Bool
    let spinningDisc: Bool?

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkCache
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0
    @State private var cachedImage: PlatformImage?
    @State private var url: URL?
    /// Associates local image state with its source id to prevent stale artwork.
    @State private var displayedId: String?
    /// The id the task found to have no cover, so it shows the placeholder.
    @State private var missingId: String?
    @State private var ramHit = RAMSnapshot()
    /// Re-runs the body after the task drops a snapshot it was showing.
    @State private var snapshotClears = 0

    init(id: String, size: Int?, tier: ArtworkTier?, cornerRadius: CGFloat, placeholderSystemImage: String,
         initialImage: PlatformImage?, loadingEnabled: Bool = true, spinningDisc: Bool? = nil) {
        self.id = id
        self.size = size
        self.tier = tier
        self.cornerRadius = cornerRadius
        self.placeholderSystemImage = placeholderSystemImage
        self.loadingEnabled = loadingEnabled
        self.spinningDisc = spinningDisc
        _cachedImage = State(initialValue: initialImage)
        _displayedId = State(initialValue: initialImage == nil ? nil : id)
    }

    private var resolvedTier: ArtworkTier {
        tier ?? ((size ?? 0) >= 480 ? .hero : .thumb)
    }

    /// The RAM-cache hit for this id, tier and upload version, read once when the body first sees
    /// them. The cache isn't observed, so this is a snapshot; the task still resolves everything else.
    private func ramSnapshot() -> PlatformImage? {
        guard loadingEnabled else { return nil }
        let tier = resolvedTier
        return ramHit.image(for: id, key: "\(id)@\(tier.rawValue):\(coverArtUploadVersion)") {
            artworkCache.cachedImage(for: id, tier: tier)
        }
    }

    /// The image the body shows: this id's own state first, then a RAM hit, then whatever an
    /// earlier id left until the task replaces it.
    private func shownImage(snapshot: PlatformImage?) -> PlatformImage? {
        displayedId == id ? (cachedImage ?? snapshot) : (snapshot ?? cachedImage)
    }

    var body: some View {
        let _ = snapshotClears
        let snapshot = ramSnapshot()
        let shown = shownImage(snapshot: snapshot)
        // The missing-cover record is read like the RAM cache, as a snapshot, so a cover already
        // known to be missing shows its placeholder on the first pass instead of the loading tile.
        let knownMissing = missingId == id || artworkCache.isMissing(id)
        // An earlier id's image gives way at once to a cover known to be missing.
        let ownsShown = displayedId == id || snapshot != nil
        let phase = CoverArtPhase.resolve(id: id, hasImage: shown != nil && (ownsShown || !knownMissing),
                                          isKnownMissing: knownMissing)
        ZStack {
            switch phase {
            case .image:
                if let shown {
                    // Keyed by the cover it shows, so an animated change of id (an album cover giving
                    // way to an artist photo) cross-fades instead of swapping in place.
                    Image(platformImage: shown)
                        .resizable()
                        .scaledToFill()
                        .id(ownsShown ? id : displayedId ?? id)
                        .transition(.opacity)
                }
            case .missing:
                missing
                    .transition(.opacity)
            case .loading:
                AsyncImage(url: url, transaction: Transaction(animation: CoverArtView.arrival)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .failure:
                        missing
                            .onAppear {
                                artworkCache.noteLoadFailed(id)
                                missingId = id
                            }
                    case .empty:
                        loadingTile
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .task(id: "\(loadingEnabled):\(id):\(coverArtUploadVersion)") {
            guard loadingEnabled else { return }
            if url != nil { url = nil }
            // A cover invalidated since (a new upload) loads again rather than staying missing.
            if missingId == id, !artworkCache.isMissing(id) { missingId = nil }
            guard !id.isEmpty else { return }
            let t = resolvedTier
            let isLocal = id.hasPrefix("local:")
            let online = container?.serverState.isOnline ?? true

            // A RAM hit applies at once, without waiting on the load path. When the body already
            // shows it from the snapshot, leave the state alone so the cover doesn't render twice.
            if let ram = artworkCache.cachedImage(for: id, tier: t) {
                if shownImage(snapshot: ramSnapshot()) !== ram { apply(ram, for: id) }
                return
            }

            if online || isLocal, let image = await artworkCache.load(coverArtId: id, tier: t) {
                guard !Task.isCancelled else { return }
                apply(image, for: id, animated: true)
                return
            }
            guard !Task.isCancelled else { return }

            if isLocal || artworkCache.hasNoArtwork(id) {
                showMissing()
                return
            }
            if displayedId == id || ramSnapshot() != nil { return }

            // Prefer the tiered cache, then the untagged file stored for offline tracks.
            for diskId in ["\(id)@\(t.rawValue)", id] {
                if let baseURL = await container?.downloadService.localCoverArtURL(forId: diskId),
                   let decoded = await Self.decodedImage(at: baseURL, maxDimension: t.decodePixels) {
                    guard !Task.isCancelled else { return }
                    // A download from before the app recognised the server's stand-in image.
                    if decoded.isServerPlaceholder {
                        showMissing()
                        return
                    }
                    apply(decoded.image, for: id, animated: true)
                    return
                }
                guard !Task.isCancelled else { return }
            }

            if t != .thumb, let ramThumb = artworkCache.cachedImage(for: id, tier: .thumb) {
                apply(ramThumb, for: id, animated: true)
                return
            }

            // The load failed on the way (offline, a timeout, a server error) and there's no copy
            // on disk: the disc, until the cache's recheck time lets the next pass ask again.
            if artworkCache.isMissing(id) {
                showMissing()
                return
            }

            cachedImage = nil
            displayedId = nil
            let fallbackURL = await container?.libraryService.coverArtURL(id: id, size: size)
            guard !Task.isCancelled else { return }
            url = fallbackURL
        }
    }

    private func apply(_ image: PlatformImage, for resolvedId: String, animated: Bool = false) {
        withAnimation(animated ? CoverArtView.arrival : nil) {
            cachedImage = image
            displayedId = resolvedId
            missingId = nil
            url = nil
        }
    }

    /// The cover is missing: the placeholder fades in over the loading tile.
    private func showMissing() {
        if ramHit.clear() { snapshotClears += 1 }
        withAnimation(CoverArtView.arrival) {
            cachedImage = nil
            displayedId = nil
            missingId = id
        }
    }

    /// Decodes a local cover file off the main actor at `maxDimension`, reusing the cache's ImageIO
    /// thumbnail path so the base-file fallback decodes identically to the tiered cache.
    private static func decodedImage(at url: URL, maxDimension: Int) async -> DecodedArtwork? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil as DecodedArtwork? }
            return ArtworkImageCache.thumbnailImage(from: data, maxDimension: maxDimension).map(DecodedArtwork.init)
        }.value
    }

    /// Static: a repeating pulse per cover kept the render loop busy while scrolling. Visible on a
    /// black background, so a loading cover reads as a tile, not a hole.
    private var loadingTile: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(MissingCoverDisc.tileFill)
    }

    /// What stands in for the missing cover; decorative, as the item's title labels it.
    @ViewBuilder private var missing: some View {
        switch CoverArtPlaceholder(symbol: placeholderSystemImage) {
        case .disc:
            if let spinningDisc {
                MinidiscLogoView(isSpinning: spinningDisc)
                    .accessibilityHidden(true)
            } else {
                MissingCoverDisc(cornerRadius: cornerRadius, isLarge: resolvedTier == .hero)
            }
        case .symbol(let name):
            ZStack {
                LinearGradient(
                    colors: [MinidiscColors.accent.opacity(0.25), MinidiscColors.accent.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(symbol: name)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
        }
    }
}

/// The RAM hit a cover's body last showed, read once per id, tier and upload version. A miss after
/// the version changes keeps showing the id's earlier image until the task replaces it, as the
/// view's own state does. Not observable: the body writes it, and that must not invalidate the view.
@MainActor
private final class RAMSnapshot {
    private var key: String?
    private var id: String?
    private var image: PlatformImage?

    func image(for id: String, key: String, read: () -> PlatformImage?) -> PlatformImage? {
        if key != self.key {
            self.key = key
            if let hit = read() {
                image = hit
            } else if id != self.id {
                image = nil
            }
            self.id = id
        }
        return image
    }

    /// The task found nothing to show: stop showing the snapshot until the key changes. Returns
    /// whether it was showing one, in which case the body has to run again.
    func clear() -> Bool {
        defer { image = nil }
        return image != nil
    }
}
