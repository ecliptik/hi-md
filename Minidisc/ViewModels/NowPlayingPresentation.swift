import Foundation

/// What the Mac's large Now Playing view and its MiniPlayer show beside the song: synced lyrics or
/// the queue.
nonisolated enum NowPlayingSidePane: String, CaseIterable, Sendable {
    case lyrics
    case queue

    /// Lyrics only when the song can have them (not radio or a local file); otherwise the queue.
    static func resolved(_ requested: NowPlayingSidePane, canShowLyrics: Bool) -> NowPlayingSidePane {
        requested == .lyrics && !canShowLyrics ? .queue : requested
    }
}

/// Text for the Now Playing views.
nonisolated enum NowPlayingText {
    /// "Artist — Album", as the Music app's player shows it; whichever is missing is left out.
    static func subtitle(artist: String?, album: String?) -> String? {
        let parts = [artist, album].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    /// White text over the artwork backdrop. `PlayerBackgroundPalette` keeps every backdrop colour
    /// at or under this relative luminance.
    static let backdropLuminanceCap = 0.09
    static let primaryOpacity = 1.0
    /// Secondary text (artist, times, lyrics not yet sung) stays at least 4.5:1 against the
    /// brightest backdrop the palette allows.
    static let secondaryOpacity = 0.78

    /// The WCAG contrast of white at `opacity` blended over a backdrop of relative luminance
    /// `backgroundLuminance` (a grey of that luminance, the worst case for any hue at that level).
    static func contrastOfWhite(opacity: Double, backgroundLuminance: Double) -> Double {
        let background = srgb(fromLuminance: backgroundLuminance)
        let blended = opacity + (1 - opacity) * background
        let foreground = luminance(ofGrey: blended)
        return (max(foreground, backgroundLuminance) + 0.05) / (min(foreground, backgroundLuminance) + 0.05)
    }

    /// Relative luminance of an sRGB grey, as `PlayerBackgroundPalette.luminance` computes it.
    static func luminance(ofGrey value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// The sRGB grey value with relative luminance `luminance`.
    static func srgb(fromLuminance luminance: Double) -> Double {
        let clamped = min(max(luminance, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}

/// The MiniPlayer window's two sizes: the controls alone, or with lyrics or the queue below.
nonisolated enum MiniPlayerLayout {
    static let width: Double = 320
    static let compactHeight: Double = 156
    static let expandedHeight: Double = 520
    static let minimumExpandedHeight: Double = 360

    static func height(expanded: Bool) -> Double { expanded ? expandedHeight : compactHeight }
}
