import Testing
@testable import Minidisc

/// The Mac main window's lyrics panel, on the window's own background in the light and dark
/// appearances: its lines take the system's primary label colour instead of the players' white.
@Suite("Window lyrics contrast")
struct WindowLyricsContrastTests {
    /// macOS 27's label colour (`.primary`), resolved in each appearance: black or white at
    /// 0.847 alpha.
    private static let labelAlpha = 0.847

    /// The backgrounds the panel can sit on, resolved in each appearance: the window and text
    /// backgrounds (white, #1E1E1E), the under-page grey (#F6F6F6, #282828), and the older,
    /// greyer window background (#ECECEC, #323232) as a margin.
    private static let lightBackgrounds = [1.0, 0.9647, 0.9255].map { WCAGContrast.RGB(red: $0, green: $0, blue: $0) }
    private static let darkBackgrounds = [0.1176, 0.1569, 0.1961].map { WCAGContrast.RGB(red: $0, green: $0, blue: $0) }

    /// The worst contrast of a line at `opacity` (its depth's opacity of `.primary`).
    private static func worst(opacity: Double, dark: Bool) -> Double {
        let label = dark ? WCAGContrast.RGB.white : WCAGContrast.RGB.black
        return (dark ? darkBackgrounds : lightBackgrounds).map { background in
            WCAGContrast.ratio(label.composited(over: background, opacity: labelAlpha * opacity), background)
        }.min()!
    }

    @Test func onlyTheMainWindowPanelUsesSystemColours() {
        #expect(LyricsTypography.mainWindowPanel.usesSystemColors)
        // The players always sit on a dark cover backdrop and keep their white.
        #expect(!LyricsTypography.iPhone.usesSystemColors)
        #expect(!LyricsTypography.scaled(forWidth: 600).usesSystemColors)
        #expect(!LyricsTypography.fullScreen(FullScreenLyricsMetrics(width: 1400, height: 900)).usesSystemColors)
        // The panel keeps the iPhone's dimming, without blur.
        #expect(LyricsTypography.mainWindowPanel.depth == .dimmed)
    }

    @Test(arguments: [false, true])
    func theLineBeingSungReachesAA(dark: Bool) {
        let current = LyricsLineAppearance.line(atDistance: 0, depth: LyricsTypography.mainWindowPanel.depth,
                                                prefersLegibility: false)
        #expect(Self.worst(opacity: current.opacity, dark: dark) >= 4.5)
    }

    @Test(arguments: [false, true])
    func theOtherLinesKeepLargeTextContrast(dark: Bool) {
        let depth = LyricsTypography.mainWindowPanel.depth
        for legible in [false, true] {
            for distance in 1...6 {
                let line = LyricsLineAppearance.line(atDistance: distance, depth: depth, prefersLegibility: legible)
                #expect(line.blur == 0)
                #expect(Self.worst(opacity: line.opacity, dark: dark) >= 3, "line \(distance), legible \(legible)")
            }
        }
    }
}
