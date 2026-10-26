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

    /// Clicking a pane's button: it shows that pane, or hides the side pane when that pane is
    /// already showing, so Lyrics turns the lyrics on and off.
    static func afterClicking(_ clicked: NowPlayingSidePane, requested: NowPlayingSidePane, isHidden: Bool,
                              canShowLyrics: Bool) -> (requested: NowPlayingSidePane, isHidden: Bool) {
        let shown = resolved(requested, canShowLyrics: canShowLyrics)
        if !isHidden, shown == clicked { return (requested, true) }
        return (clicked, false)
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

/// The Mac Now Playing view's sizes for a window: the player column grows with the window, as
/// the Music app's does, and the artwork takes what the height leaves after the controls.
nonisolated struct NowPlayingMetrics: Equatable, Sendable {
    /// Points around the content and between the player and the side pane.
    static let horizontalInset: Double = 48
    static let verticalInset: Double = 64
    static let columnGap: Double = 56
    /// The column's width at scale 1.
    static let baseColumn: Double = 360

    /// 1 in the smallest window, up to 1.6 on a large screen.
    let scale: Double
    /// The artwork's side, which is also the width of the song, the scrubber and the transport.
    let artworkSide: Double
    /// The side pane's width, or 0 when it's hidden.
    let paneWidth: Double

    var titleSize: Double { (22 * scale).rounded() }
    var subtitleSize: Double { (17 * scale).rounded() }
    var timeSize: Double { (11 * scale).rounded() }
    var transportSize: Double { (24 * scale).rounded() }
    var playSize: Double { (44 * scale).rounded() }
    var columnSpacing: Double { (22 * scale).rounded() }

    /// What the column needs under the artwork: the song, the scrubber, the transport and gaps.
    static func controlsHeight(scale: Double) -> Double { 230 * scale }

    init(width: Double, height: Double, showsPane: Bool) {
        let content = max(width - 2 * Self.horizontalInset, 0)
        let column = showsPane ? max((content - Self.columnGap) / 2, 0) : min(content, 720)
        let scale = min(max(column / Self.baseColumn, 1), 1.6)
        self.scale = scale
        let byHeight = height - 2 * Self.verticalInset - Self.controlsHeight(scale: scale)
        artworkSide = max(min(column, byHeight, 720), 200)
        paneWidth = showsPane ? column : 0
    }
}
