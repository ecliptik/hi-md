import SwiftUI

/// Resolved artwork color and foreground colors shared by detail-page content and backgrounds.
struct PlaylistTheme: Equatable, Sendable {
    /// Base theme color. `.clear` = not resolved yet → system-adaptive fallback (no blend).
    let dominantColor: Color
    /// Black or white content by WCAG contrast, and the secondary opacity it needs. Nil until the
    /// colour is known.
    private let readable: ReadableContent.Resolution?

    init(dominantColor: Color) {
        self.dominantColor = dominantColor
        readable = dominantColor == .clear ? nil
            : WCAGContrast.RGB(dominantColor.rgbComponents).map { ReadableContent.resolve(backgrounds: [$0]) }
    }

    var isThemed: Bool { dominantColor != .clear }
    var isLight: Bool { readable?.usesDarkContent ?? false }

    /// The page colour: the cover colour, nudged darker or lighter only in the narrow mid-tone band
    /// where neither black nor white text reached 4.5:1.
    var backgroundColor: Color {
        guard let stop = readable?.backgrounds.first else { return dominantColor }
        return Color(red: stop.red, green: stop.green, blue: stop.blue)
    }

    var contentColor: Color { isThemed ? (isLight ? .black : .white) : .primary }
    /// At least 70%, raised where 70% falls under 4.5:1 on this colour.
    var secondaryContentColor: Color {
        guard isThemed else { return .secondary }
        return contentColor.opacity(readable?.secondaryOpacity ?? 0.7)
    }
}
