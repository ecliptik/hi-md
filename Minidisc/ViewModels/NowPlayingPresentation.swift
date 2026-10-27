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
        let parts = subtitleParts(artist: artist, album: album)
        let joined = [parts.artist, parts.album].compactMap { $0 }
        return joined.isEmpty ? nil : joined.joined(separator: " — ")
    }

    /// The artist and the album, trimmed, each nil when missing. The views lay them out side by
    /// side so the album truncates before the artist does.
    static func subtitleParts(artist: String?, album: String?) -> (artist: String?, album: String?) {
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        return (clean(artist), clean(album))
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

/// The type and controls of the Mac's player column, in Now Playing and full-screen lyrics. As in
/// the Music app they grow only a little with the window, the artwork taking the extra room: at
/// about 1,470 points the title is 17 points on one line, "Artist — Album" 14, the transport 23
/// with a 31-point play button, and the heart and menu 24-point buttons.
nonisolated struct NowPlayingControlSizes: Equatable, Sendable {
    static let smallWidth: Double = 900
    static let largeWidth: Double = 2560

    /// 0 in a window 900 points wide or less, 1 at 2,560 points or more.
    let growth: Double

    init(windowWidth: Double) {
        growth = min(max((windowWidth - Self.smallWidth) / (Self.largeWidth - Self.smallWidth), 0), 1)
    }

    private func size(_ small: Double, _ large: Double) -> Double {
        (small + (large - small) * growth).rounded()
    }

    var titleSize: Double { size(15, 20) }
    var subtitleSize: Double { size(13, 16) }
    var timeSize: Double { size(10, 12) }
    var transportSize: Double { size(20, 28) }
    var playSize: Double { size(28, 38) }
    /// The heart's and the menu's buttons, beside the title.
    var songButtonSize: Double { size(22, 28) }
}

/// The Mac Now Playing view's sizes for a window: the player column grows with the window, as
/// the Music app's does, and the artwork takes what the height leaves after the controls. The
/// type and the controls grow only gently (`NowPlayingControlSizes`).
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
    let controls: NowPlayingControlSizes

    var titleSize: Double { controls.titleSize }
    var subtitleSize: Double { controls.subtitleSize }
    var timeSize: Double { controls.timeSize }
    var transportSize: Double { controls.transportSize }
    var playSize: Double { controls.playSize }
    var songButtonSize: Double { controls.songButtonSize }
    var columnSpacing: Double { (18 * scale).rounded() }

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
        controls = NowPlayingControlSizes(windowWidth: width)
    }
}

/// The Mac's full-screen lyrics for a window: the artwork, the song and its controls in a column
/// on the left, about 40% of the width, and the lyrics on the right in huge lines, only about
/// four of them showing. The artwork and the lines grow with the window, the lines being about
/// 60 points in a 1,000-point window; the song's type and the controls grow only gently.
nonisolated struct FullScreenLyricsMetrics: Equatable, Sendable {
    /// 1 in a 1,000-point window, from 0.85 to 1.6.
    let scale: Double
    let horizontalInset: Double
    let verticalInset: Double
    /// Between the player column and the lyrics.
    let columnGap: Double
    /// The artwork's side, which is also the width of the song, the scrubber and the transport.
    let artworkSide: Double
    let lyricsWidth: Double
    /// The lyric lines' point size.
    let lineSize: Double
    /// The height the lyrics show in.
    let lyricsHeight: Double
    /// The player column's type and controls, which grow only gently.
    let controls: NowPlayingControlSizes

    var lineSpacing: Double { (lineSize * 0.42).rounded() }
    var titleSize: Double { controls.titleSize }
    var subtitleSize: Double { controls.subtitleSize }
    var timeSize: Double { controls.timeSize }
    var transportSize: Double { controls.transportSize }
    var playSize: Double { controls.playSize }
    var songButtonSize: Double { controls.songButtonSize }
    var columnSpacing: Double { (12 * scale).rounded() }
    /// Roughly how many lines show, if none wraps.
    static let visibleLines = 4.2

    /// What the column needs under the artwork: the song, the scrubber, the transport and gaps.
    static func controlsHeight(scale: Double) -> Double { 170 * scale }

    init(width: Double, height: Double) {
        let scale = min(max(width / 1000, 0.85), 1.6)
        self.scale = scale
        horizontalInset = min(max(width * 0.06, 40), 120).rounded()
        verticalInset = min(max(height * 0.08, 32), 96).rounded()
        columnGap = min(max(width * 0.05, 36), 110).rounded()
        let content = max(width - 2 * horizontalInset - columnGap, 0)
        let byHeight = height - 2 * verticalInset - Self.controlsHeight(scale: scale)
        artworkSide = max(min(content * 0.45, byHeight), 160)
        lyricsWidth = max(content - artworkSide, 0)
        // Slower than the window, so a large screen's lines don't hold only a word or two.
        let size = 60 * pow(scale, 0.7)
        lineSize = min(max(min(size, lyricsWidth / 7.5), 36), 84).rounded()
        let pitch = lineSize * 1.25 + (lineSize * 0.42).rounded()
        lyricsHeight = max(min(pitch * Self.visibleLines, height - 2 * verticalInset), 0)
        controls = NowPlayingControlSizes(windowWidth: width)
    }
}
