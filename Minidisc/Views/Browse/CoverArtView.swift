import SwiftUI

// ArtworkImageCache's storage is not observed, so a read in a view body is a snapshot
// that never updates when the cover arrives. Resolve one id from a task instead.
/// Resolves cover art through the shared cache, then falls back to AsyncImage.
/// Sizes of at least 480 points use the hero tier unless `tier` overrides it.
struct CoverArtView: View {
    let id: String
    let size: Int?
    var tier: ArtworkTier? = nil
    var cornerRadius: CGFloat = 0
    var placeholderSystemImage: String = "music.note"
    var initialImage: PlatformImage? = nil
    /// Defers loading for mounted rows that are not yet visible.
    var loadingEnabled: Bool = true

    var body: some View {
        CoverArtViewContent(
            id: id,
            size: size,
            tier: tier,
            cornerRadius: cornerRadius,
            placeholderSystemImage: placeholderSystemImage,
            initialImage: initialImage,
            loadingEnabled: loadingEnabled
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

    @Environment(\.appContainer) private var container
    @Environment(ArtworkImageCache.self) private var artworkCache
    @AppStorage("coverArtUploadVersion") private var coverArtUploadVersion = 0
    @State private var cachedImage: PlatformImage?
    @State private var url: URL?
    /// Associates local image state with its source id to prevent stale artwork.
    @State private var displayedId: String?
    /// The server has no artwork for this id (it answered with its stand-in image).
    @State private var hasNoArtwork = false

    init(id: String, size: Int?, tier: ArtworkTier?, cornerRadius: CGFloat, placeholderSystemImage: String, initialImage: PlatformImage?, loadingEnabled: Bool = true) {
        self.id = id
        self.size = size
        self.tier = tier
        self.cornerRadius = cornerRadius
        self.placeholderSystemImage = placeholderSystemImage
        self.loadingEnabled = loadingEnabled
        _cachedImage = State(initialValue: initialImage)
        _displayedId = State(initialValue: initialImage == nil ? nil : id)
    }

    private var resolvedTier: ArtworkTier {
        tier ?? ((size ?? 0) >= 480 ? .hero : .thumb)
    }

    var body: some View {
        ZStack {
            if let cached = cachedImage {
                Image(platformImage: cached)
                    .resizable()
                    .scaledToFill()
            } else if id.hasPrefix("local:") || hasNoArtwork {
                placeholder
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        GeometryReader { geo in
                            SkeletonBlock(
                                width: geo.size.width,
                                height: geo.size.height,
                                cornerRadius: cornerRadius
                            )
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .task(id: "\(loadingEnabled):\(id):\(coverArtUploadVersion)") {
            guard loadingEnabled else { return }
            url = nil
            hasNoArtwork = false
            let t = resolvedTier
            let online = container?.serverState.isOnline ?? true

            // A RAM hit applies at once, without waiting on the load path.
            if let ram = artworkCache.cachedImage(for: id, tier: t) {
                apply(ram, for: id)
                return
            }

            if online || id.hasPrefix("local:"), let image = await artworkCache.load(coverArtId: id, tier: t) {
                guard !Task.isCancelled else { return }
                apply(image, for: id)
                return
            }

            if id.hasPrefix("local:") || artworkCache.hasNoArtwork(id) {
                cachedImage = nil
                displayedId = nil
                hasNoArtwork = !id.hasPrefix("local:")
                return
            }
            if displayedId == id { return }

            // Prefer the tiered cache, then the untagged file stored for offline tracks.
            for diskId in ["\(id)@\(t.rawValue)", id] {
                if let baseURL = await container?.downloadService.localCoverArtURL(forId: diskId),
                   let decoded = await Self.decodedImage(at: baseURL, maxDimension: t.decodePixels) {
                    guard !Task.isCancelled else { return }
                    // A download from before the app recognised the server's stand-in image.
                    if decoded.isServerPlaceholder {
                        cachedImage = nil
                        displayedId = nil
                        hasNoArtwork = true
                        return
                    }
                    apply(decoded.image, for: id)
                    return
                }
                guard !Task.isCancelled else { return }
            }

            if t != .thumb, let ramThumb = artworkCache.cachedImage(for: id, tier: .thumb) {
                apply(ramThumb, for: id)
                return
            }

            cachedImage = nil
            displayedId = nil
            let fallbackURL = await container?.libraryService.coverArtURL(id: id, size: size)
            guard !Task.isCancelled else { return }
            url = fallbackURL
        }
    }

    private func apply(_ image: PlatformImage, for resolvedId: String) {
        cachedImage = image
        displayedId = resolvedId
        url = nil
    }

    /// Decodes a local cover file off the main actor at `maxDimension`, reusing the cache's ImageIO
    /// thumbnail path so the base-file fallback decodes identically to the tiered cache.
    private static func decodedImage(at url: URL, maxDimension: Int) async -> DecodedArtwork? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return nil as DecodedArtwork? }
            return ArtworkImageCache.thumbnailImage(from: data, maxDimension: maxDimension).map(DecodedArtwork.init)
        }.value
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [MinidiscColors.accent.opacity(0.25), MinidiscColors.accent.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if placeholderSystemImage == Self.musicPlaceholder {
                // Albums and songs without artwork get the Minidisc logo.
                Image(.minidiscLogoThumb)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(0.78)
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: placeholderSystemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let musicPlaceholder = "music.note"
}
