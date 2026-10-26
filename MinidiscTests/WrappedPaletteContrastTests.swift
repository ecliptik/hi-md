import Testing
@testable import Minidisc

/// White text on the Wrapped gradients (accessibility audit 2026-10-25, H5).
@Suite("Wrapped palette contrast")
struct WrappedPaletteContrastTests {
    private nonisolated static let years = Array(2024...2031)

    @Test("White text reaches 4.5:1 on every gradient stop", arguments: years)
    func whiteTextOnEveryStop(_ year: Int) {
        for stop in WrappedYearPalette.legibleStops(for: year) {
            let ratio = WCAGContrast.ratio(.white, stop)
            #expect(ratio >= 4.5, "\(year) \(stop): \(ratio)")
        }
    }

    /// The stops and every blend of them the mesh can draw, on a 10% grid.
    private static func blends(for year: Int) -> [WCAGContrast.RGB] {
        let stops = WrappedYearPalette.legibleStops(for: year)
        var result: [WCAGContrast.RGB] = []
        for i in 0...10 {
            for j in 0...(10 - i) {
                let (a, b, c) = (Double(i) / 10, Double(j) / 10, Double(10 - i - j) / 10)
                result.append(WCAGContrast.RGB(
                    red: stops[0].red * a + stops[1].red * b + stops[2].red * c,
                    green: stops[0].green * a + stops[1].green * b + stops[2].green * c,
                    blue: stops[0].blue * a + stops[1].blue * b + stops[2].blue * c))
            }
        }
        return result
    }

    @Test("Captions reach 4.5:1 on every stop and blend (contrast sweep 2026-10-26)", arguments: years)
    func captionsReachAA(_ year: Int) {
        for background in Self.blends(for: year) {
            let text = WCAGContrast.RGB.white.composited(over: background,
                                                         opacity: WrappedYearPalette.secondaryTextOpacity)
            let ratio = WCAGContrast.ratio(text, background)
            #expect(ratio >= 4.5, "\(year) \(background): \(ratio)")
        }
    }

    @Test("White text on a translucent chip reaches 4.5:1", arguments: years)
    func chipText(_ year: Int) {
        for background in Self.blends(for: year) {
            let chip = WCAGContrast.RGB.white.composited(over: background, opacity: WrappedYearPalette.chipFillOpacity)
            let ratio = WCAGContrast.ratio(.white, chip)
            #expect(ratio >= 4.5, "\(year) \(chip): \(ratio)")
        }
    }

    @Test("Each palette is darkened as a whole, so its colours keep their balance", arguments: years)
    func darkeningIsUniform(_ year: Int) throws {
        let source = WrappedYearPalette.sourceStops(for: year)
        let legible = WrappedYearPalette.legibleStops(for: year)
        try #require(source.count == legible.count)
        func sum(_ c: WCAGContrast.RGB) -> Double { c.red + c.green + c.blue }
        let factor = sum(legible[0]) / sum(source[0])
        for (before, after) in zip(source, legible) {
            #expect(abs(after.red - before.red * factor) < 1e-9)
            #expect(abs(after.green - before.green * factor) < 1e-9)
            #expect(abs(after.blue - before.blue * factor) < 1e-9)
        }
        #expect(factor <= 1)
    }

    @Test func darkPalettesAreLeftAlone() {
        // 2029 (midnight) already carries white text at over 8:1.
        #expect(WrappedYearPalette.legibleStops(for: 2029) == WrappedYearPalette.sourceStops(for: 2029))
    }

    @Test func paletteDoesNotDarkenMoreThanNeeded() {
        // The brightest stop of a darkened palette lands close to the limit, not far below it.
        for year in Self.years where WrappedYearPalette.legibleStops(for: year) != WrappedYearPalette.sourceStops(for: year) {
            let brightest = WrappedYearPalette.legibleStops(for: year).map(WCAGContrast.luminance).max() ?? 0
            #expect(brightest > WrappedYearPalette.maxStopLuminance - 0.005, "\(year): \(brightest)")
        }
    }

    @Test func cyclesEveryEightYears() {
        #expect(WrappedYearPalette.legibleStops(for: 2026) == WrappedYearPalette.legibleStops(for: 2034))
    }
}
