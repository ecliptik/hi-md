import Foundation

/// How the current song's large cover (Now Playing, the MiniPlayer, full-screen lyrics, the
/// player bar, the iPhone's full player) moves from the image it shows to the next one.
///
/// The same image stays exactly as it is, so a song from the same album changes nothing on screen.
/// Another image cross-fades in over the one showing, which stays fully opaque underneath until
/// the new one has covered it, so the change never dips to the backdrop. The first image, and any
/// change under Reduce Motion, swaps at once.
nonisolated enum ArtworkChange: Equatable, Sendable {
    /// Nothing to do: the image showing is the one asked for.
    case none
    /// Show the new image at once.
    case swap
    /// Fade the new image in over the old one.
    case crossfade

    /// What the cover shows: the cover id and the image itself, which can change under the same
    /// id (a larger tier, a new upload).
    struct Shown: Equatable, Sendable {
        let coverID: String
        let image: ObjectIdentifier
    }

    /// The fade's length.
    static let duration: TimeInterval = 0.25

    static func between(_ old: Shown?, _ new: Shown, reduceMotion: Bool) -> ArtworkChange {
        guard let old else { return .swap }
        // The same picture under the same id: a song from the same album, or the view redrawn.
        if old.image == new.image { return old.coverID == new.coverID ? .none : .swap }
        return reduceMotion ? .swap : .crossfade
    }
}
