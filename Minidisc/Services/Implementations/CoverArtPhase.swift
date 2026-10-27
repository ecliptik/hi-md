import Foundation

/// What a cover shows. The one place the app decides between the artwork, the neutral tile a
/// cover shows while it loads, and the MiniDisc that stands in for a cover that's missing.
///
/// The disc only appears once a cover is known to be missing (the item has no cover id, or the
/// cache recorded that loading it failed or the server has none), never while it may still
/// arrive, so a real cover doesn't pop in over the disc.
nonisolated enum CoverArtPhase: Equatable, Sendable {
    /// Not loaded yet: the neutral tile.
    case loading
    /// The artwork.
    case image
    /// No artwork to load: the MiniDisc, or the placeholder symbol of an artist or a station.
    case missing

    /// - Parameters:
    ///   - id: the cover's id; nil or empty when the item has no cover.
    ///   - hasImage: the artwork is in hand.
    ///   - isKnownMissing: the cache has recorded that this cover can't be loaded
    ///     (`ArtworkImageCache.isMissing`).
    static func resolve(id: String?, hasImage: Bool, isKnownMissing: Bool) -> CoverArtPhase {
        if hasImage { return .image }
        guard let id, !id.isEmpty else { return .missing }
        return isKnownMissing ? .missing : .loading
    }
}

/// What stands in for a missing cover, from the placeholder symbol a view asks for: albums, songs
/// and playlists get the MiniDisc; artists and radio stations keep their own symbol.
nonisolated enum CoverArtPlaceholder: Equatable, Sendable {
    case disc
    case symbol(String)

    /// The symbol `CoverArtView` takes by default, for songs.
    static let defaultSymbol = "music.note"

    init(symbol name: String) {
        switch name {
        case Self.defaultSymbol, MinidiscSymbol.album, MinidiscSymbol.albumFill: self = .disc
        default: self = .symbol(name)
        }
    }
}
