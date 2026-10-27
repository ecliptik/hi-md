import SwiftUI

@Observable
@MainActor
final class FullPlayerViewModel {
    static let defaultColors: [Color] = Array(repeating: .black, count: 4)

    private(set) var backgroundColors: [Color] = FullPlayerViewModel.defaultColors
    private(set) var coverArtID: String?
    /// The cover whose own colours the backdrop shows; nil while it still has the default black.
    private(set) var paletteID: String?

    var contentColor: Color { .white }
    var secondaryContentColor: Color { Color.white.opacity(PlayerBackgroundPalette.secondaryOpacity) }
    /// Glyphs and large text that need 3:1 over the backdrop.
    var dimmedContentColor: Color { Color.white.opacity(PlayerBackgroundPalette.dimmedOpacity) }

    /// The palette key of the MiniDisc that stands in for a missing cover. Its colours come from
    /// the image the Lock Screen shows for such a song, the cartridge on gold.
    static let discPaletteKey = "minidisc.no-artwork"
    static let discPaletteImageName = "NowPlayingNoArtwork"

    /// What the backdrop shows while a new cover's bands are worked out: nil keeps the colours on
    /// screen, so a song change goes straight from one palette to the next and never through
    /// black. Only a backdrop still on the default takes the cover's average in the meantime.
    static func interimColors(showingPaletteOf paletteID: String?, average: Color?) -> [Color]? {
        guard paletteID == nil, let average else { return nil }
        return Array(repeating: average, count: 4)
    }

    /// The colours for a view to draw for `coverArtId` before this model has caught up with it,
    /// as on the player's first frame: once it shows a palette it keeps it until the next one is
    /// ready; before that, the cover's memoized colours.
    func displayedColors(for coverArtId: String, colorExtractor: DominantColorExtractor) -> [Color] {
        if paletteID != nil || coverArtID == coverArtId { return backgroundColors }
        return colorExtractor.cachedBackgroundColors(for: coverArtId)
            ?? colorExtractor.cachedColor(for: coverArtId).map { Array(repeating: $0, count: 4) }
            ?? backgroundColors
    }

    /// - Parameter discWhenMissing: a song whose cover is missing shows the spinning disc, so its
    ///   backdrop takes the disc's gold; a station without a cover keeps the dark backdrop.
    func updateColors(for coverArtId: String?, discWhenMissing: Bool = true, colorExtractor: DominantColorExtractor,
                      container: AppContainer?, reduceMotion: Bool = false) async {
        coverArtID = coverArtId
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.25)
        guard let coverArtId else {
            show(Self.defaultColors, of: nil, animation: animation)
            return
        }
        if let colors = colorExtractor.cachedBackgroundColors(for: coverArtId) {
            show(colors, of: coverArtId, animation: animation)
            return
        }
        let artworkCache = container?.artworkImageCache
        // A cover the server has none of goes straight to the disc's colours.
        if discWhenMissing, artworkCache?.hasNoArtwork(coverArtId) == true,
           let colors = await Self.discColors(colorExtractor) {
            guard !Task.isCancelled, coverArtID == coverArtId else { return }
            show(colors, of: coverArtId, animation: animation)
            return
        }
        // The previous song's palette stays until this cover's bands are ready.
        let average = colorExtractor.cachedColor(for: coverArtId)
        if let interim = Self.interimColors(showingPaletteOf: paletteID, average: average) {
            withAnimation(animation) { backgroundColors = interim }
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
            if artworkCache.phase(for: coverArtId) == .missing {
                // The cover turned out to be missing: the player shows the disc, so take its
                // colours; a station shows its symbol on the dark backdrop.
                guard discWhenMissing else {
                    show(Self.defaultColors, of: coverArtId, animation: animation)
                    return
                }
                guard let colors = await Self.discColors(colorExtractor),
                      !Task.isCancelled, coverArtID == coverArtId else { return }
                show(colors, of: coverArtId, animation: animation)
            } else if let average {
                // Nothing to sample yet: at least this cover's own average, not the last song's.
                show(Array(repeating: average, count: 4), of: coverArtId, animation: animation)
            }
            return
        }
        guard let colors = await colorExtractor.backgroundColors(for: coverArtId, image: resolvedImage),
              !Task.isCancelled, coverArtID == coverArtId else { return }
        show(colors, of: coverArtId, animation: animation)
    }

    /// Puts `colors` up for `id`, animating only an actual change: the same palette again (the
    /// same cover, or another id for the same artwork) leaves the backdrop alone.
    private func show(_ colors: [Color], of id: String?, animation: Animation?) {
        paletteID = id
        guard colors != backgroundColors else { return }
        withAnimation(animation) { backgroundColors = colors }
    }

    /// The backdrop bands of the MiniDisc on gold, extracted once and kept under their own key.
    static func discColors(_ colorExtractor: DominantColorExtractor) async -> [Color]? {
        if let cached = colorExtractor.cachedBackgroundColors(for: discPaletteKey) { return cached }
        guard let image = PlatformImage(named: discPaletteImageName) else { return nil }
        return await colorExtractor.backgroundColors(for: discPaletteKey, image: image)
    }
}
