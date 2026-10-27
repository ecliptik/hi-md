import SwiftUI

/// The size of the player's lyric lines and the room around them. The iPhone keeps the default
/// (title 2, its own Dynamic Type size); the Mac's Now Playing view and MiniPlayer set a point
/// size that grows with the pane, as the Music app's Mac lyrics do.
nonisolated struct LyricsTypography: Equatable, Sendable {
    /// The lines' point size, or nil for the iPhone's title 2.
    var lineSize: Double?
    /// The gap between lines.
    var lineSpacing: Double = 32
    /// The inset of the lines and of the buttons above them.
    var horizontalInset: Double = 8
    var headerInset: Double = 32
    /// The full-screen and follow-along buttons above the lines. The Mac MiniPlayer leaves them
    /// out: full screen means nothing there, and the lines start right under its tabs.
    var showsHeaderButtons = true
    /// How the lines around the one being sung recede.
    var depth: LyricsLineDepth = .dimmed
    /// Untimed lyrics' point size, in regular weight at a reading size, or nil for the
    /// platform's: 17 points on the iPhone, scaling with Dynamic Type, and 15 on the Mac.
    var plainSize: Double?
    /// The system's primary and secondary text colours instead of the player's white, for a
    /// pane on the window's own background (the Mac main window's lyrics panel).
    var usesSystemColors = false

    static let iPhone = LyricsTypography()

    /// The Mac main window's lyrics panel, on the window background beside the library.
    static let mainWindowPanel = LyricsTypography(showsHeaderButtons: false, plainSize: 15, usesSystemColors: true)

    /// The Mac's full-screen lyrics: huge left-aligned lines sized by `metrics`, the lines around
    /// the one being sung blurred and faded away.
    static func fullScreen(_ metrics: FullScreenLyricsMetrics) -> LyricsTypography {
        LyricsTypography(lineSize: metrics.lineSize, lineSpacing: metrics.lineSpacing, horizontalInset: 0,
                         headerInset: 0, showsHeaderButtons: false, depth: .deep, plainSize: metrics.plainLineSize)
    }

    /// The same lines without the buttons above them.
    func withoutHeaderButtons() -> LyricsTypography {
        var copy = self
        copy.showsHeaderButtons = false
        return copy
    }

    /// The same lines, receding by `depth`.
    func withDepth(_ depth: LyricsLineDepth) -> LyricsTypography {
        var copy = self
        copy.depth = depth
        return copy
    }

    /// Large bold lines for a pane `width` points wide: about 30 pt beside the player in a
    /// 1,000-point window, up to `maximum` in a full-screen one, and never under `minimum`.
    /// Untimed lyrics read at a much smaller size that grows only a little with the pane, from
    /// `plainMinimum` to `plainMaximum`.
    static func scaled(forWidth width: Double, minimum: Double = 22, maximum: Double = 40,
                       plainMinimum: Double = 17, plainMaximum: Double = 22) -> LyricsTypography {
        let size = min(max((width / 14).rounded(), minimum), maximum)
        return LyricsTypography(lineSize: size,
                                lineSpacing: (size * 0.85).rounded(),
                                horizontalInset: 4,
                                headerInset: 4,
                                plainSize: min(max((width / 24).rounded(), plainMinimum), plainMaximum))
    }
}

private struct LyricsTypographyKey: EnvironmentKey {
    static let defaultValue = LyricsTypography.iPhone
}

extension EnvironmentValues {
    var lyricsTypography: LyricsTypography {
        get { self[LyricsTypographyKey.self] }
        set { self[LyricsTypographyKey.self] = newValue }
    }
}
