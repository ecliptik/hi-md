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
    /// The full-screen lines' point size, or nil for the iPhone karaoke view's large title.
    var karaokeLineSize: Double?

    static let iPhone = LyricsTypography()

    /// The Mac's full-screen lyrics: huge centred lines for a window `width` points wide, from
    /// 48 pt in the smallest window to 72 pt on a large screen.
    static func karaoke(forWidth width: Double) -> LyricsTypography {
        let size = min(max((width / 20).rounded(), 48), 72)
        return LyricsTypography(lineSize: nil, lineSpacing: (size * 0.75).rounded(), horizontalInset: 48,
                                headerInset: 4, showsHeaderButtons: false, karaokeLineSize: size)
    }

    /// The same lines without the buttons above them.
    func withoutHeaderButtons() -> LyricsTypography {
        var copy = self
        copy.showsHeaderButtons = false
        return copy
    }

    /// Large bold lines for a pane `width` points wide: about 30 pt beside the player in a
    /// 1,000-point window, up to `maximum` in a full-screen one, and never under `minimum`.
    static func scaled(forWidth width: Double, minimum: Double = 22, maximum: Double = 40) -> LyricsTypography {
        let size = min(max((width / 14).rounded(), minimum), maximum)
        return LyricsTypography(lineSize: size,
                                lineSpacing: (size * 0.85).rounded(),
                                horizontalInset: 4,
                                headerInset: 4)
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
