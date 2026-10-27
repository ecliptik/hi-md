import SwiftUI

@Observable
@MainActor
final class FullPlayerViewModel {
    private(set) var backgroundColors: [Color] = Array(repeating: .black, count: 4)
    private(set) var coverArtID: String?

    var contentColor: Color { .white }
    var secondaryContentColor: Color { Color.white.opacity(PlayerBackgroundPalette.secondaryOpacity) }
    /// Glyphs and large text that need 3:1 over the backdrop.
    var dimmedContentColor: Color { Color.white.opacity(PlayerBackgroundPalette.dimmedOpacity) }

    /// The palette key of the MiniDisc that stands in for a missing cover. Its colours come from
    /// the image the Lock Screen shows for such a song, the cartridge on gold.
    static let discPaletteKey = "minidisc.no-artwork"
    static let discPaletteImageName = "NowPlayingNoArtwork"

    /// - Parameter discWhenMissing: a song whose cover is missing shows the spinning disc, so its
    ///   backdrop takes the disc's gold; a station without a cover keeps the dark backdrop.
    func updateColors(for coverArtId: String?, discWhenMissing: Bool = true, colorExtractor: DominantColorExtractor,
                      container: AppContainer?, reduceMotion: Bool = false) async {
        coverArtID = coverArtId
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.25)
        guard let coverArtId else {
            withAnimation(animation) { backgroundColors = Array(repeating: .black, count: 4) }
            return
        }
        if let colors = colorExtractor.cachedBackgroundColors(for: coverArtId) {
            withAnimation(animation) { backgroundColors = colors }
            return
        }
        let artworkCache = container?.artworkImageCache
        // A cover the server has none of goes straight to the disc's colours.
        if discWhenMissing, artworkCache?.hasNoArtwork(coverArtId) == true,
           let colors = await Self.discColors(colorExtractor) {
            guard !Task.isCancelled, coverArtID == coverArtId else { return }
            withAnimation(animation) { backgroundColors = colors }
            return
        }
        // Use this cover's existing average until its bands are ready, never the previous song's colors.
        withAnimation(animation) {
            backgroundColors = Array(repeating: colorExtractor.cachedColor(for: coverArtId) ?? .black, count: 4)
        }
        guard let artworkCache else { return }
        let image = artworkCache.cachedImage(for: coverArtId, tier: .hero)
            ?? artworkCache.cachedImage(for: coverArtId, tier: .thumb)
        var resolvedImage: PlatformImage?
        if let image { resolvedImage = image }
        else { resolvedImage = await artworkCache.load(coverArtId: coverArtId, tier: .thumb) }
        guard !Task.isCancelled, coverArtID == coverArtId else { return }
        // Offline, a downloaded song's cover is the untagged file the cover view falls back to.
        if resolvedImage == nil, !artworkCache.hasNoArtwork(coverArtId),
           let fileURL = await container?.downloadService.localCoverArtURL(forId: coverArtId) {
            let decoded = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: fileURL))
                    .flatMap { ArtworkImageCache.thumbnailImage(from: $0, maxDimension: 240) }
                    .map(DecodedArtwork.init)
            }.value
            resolvedImage = decoded?.isServerPlaceholder == false ? decoded?.image : nil
            guard !Task.isCancelled, coverArtID == coverArtId else { return }
        }
        guard let resolvedImage else {
            // The cover turned out to be missing: the player shows the disc, so take its colours.
            guard discWhenMissing, artworkCache.phase(for: coverArtId) == .missing,
                  let colors = await Self.discColors(colorExtractor),
                  !Task.isCancelled, coverArtID == coverArtId else { return }
            withAnimation(animation) { backgroundColors = colors }
            return
        }
        guard let colors = await colorExtractor.backgroundColors(for: coverArtId, image: resolvedImage),
              !Task.isCancelled, coverArtID == coverArtId else { return }
        withAnimation(animation) { backgroundColors = colors }
    }

    /// The backdrop bands of the MiniDisc on gold, extracted once and kept under their own key.
    static func discColors(_ colorExtractor: DominantColorExtractor) async -> [Color]? {
        if let cached = colorExtractor.cachedBackgroundColors(for: discPaletteKey) { return cached }
        guard let image = PlatformImage(named: discPaletteImageName) else { return nil }
        return await colorExtractor.backgroundColors(for: discPaletteKey, image: image)
    }
}
