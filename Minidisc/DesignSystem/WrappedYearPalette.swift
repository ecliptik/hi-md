import SwiftUI

nonisolated enum WrappedYearPalette {
    /// Returns 3 deterministic colors derived from the given year, cycling every 8 years.
    /// Used as source palette for mesh gradient backgrounds in Wrapped hero, year card,
    /// and cover generation.
    ///
    /// White text sits straight on these gradients, so each palette is darkened as a whole
    /// (the same as a black scrim) until its brightest stop leaves white at 4.5:1 or more.
    /// Darkening every stop by the same factor keeps the palette's character, and the cap
    /// sits a little under the limit for the mesh's smoothed blending. Already-dark palettes
    /// are untouched. White text before → after (audit 2026-10-25, H5): 2024 1.97 → 4.67,
    /// 2025 3.76 → 4.71, 2026 2.44 → 4.68, 2027 2.30 → 4.68, 2028 1.87 → 4.70,
    /// 2029 8.63 (unchanged), 2030 2.74 → 4.68, 2031 4.37 → 4.68.
    static func colors(for year: Int) -> [Color] {
        legibleStops(for: year).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// The stops `colors(for:)` draws, after darkening for white text.
    static func legibleStops(for year: Int) -> [WCAGContrast.RGB] {
        legiblePalettes[paletteIndex(for: year)]
    }

    /// The brand stops before darkening.
    static func sourceStops(for year: Int) -> [WCAGContrast.RGB] {
        sourcePalettes[paletteIndex(for: year)].map(WCAGContrast.RGB.init(hex:))
    }

    /// The brightest luminance a stop may keep: a little under the 4.5:1 limit for white.
    static let maxStopLuminance = 0.175

    private static func paletteIndex(for year: Int) -> Int {
        ((year % 8) + 8) % 8
    }

    private static let sourcePalettes: [[UInt32]] = [
        [0xFF8C42, 0xC62828, 0xF9A825], // 2024, warm sunset: warm orange, deep red, golden yellow
        [0xAB47BC, 0xEC407A, 0x283593], // 2025, electric dusk: magenta purple, hot pink, deep indigo
        [0x926A0C, 0x624605, 0xD59C18], // 2026, Minidisc identity: brand gold, deep bronze, bright gold
        [0x00BCD4, 0x009688, 0x2979FF], // 2027, oceanic: cyan, teal, electric blue
        [0x2E7D32, 0xF9A825, 0x80CBC4], // 2028, botanical: forest green, sunny yellow, mint
        [0x1A237E, 0x6A1BA9, 0x0D47A1], // 2029, midnight: midnight indigo, royal purple, deep blue
        [0xFF6B6B, 0xE91E63, 0xFF7043], // 2030, flamingo: coral pink, rose red, sunset orange
        [0x607D8B, 0x5C6BC0, 0x283593], // 2031, storm: stone gray, slate blue, deep indigo
    ]

    private static let legiblePalettes: [[WCAGContrast.RGB]] = sourcePalettes.map { hexes in
        let stops = hexes.map(WCAGContrast.RGB.init(hex:))
        return stops.map { $0.scaled(by: legibilityFactor(for: stops)) }
    }

    /// The largest factor (at most 1) that brings every stop to `maxStopLuminance` or below.
    private static func legibilityFactor(for stops: [WCAGContrast.RGB]) -> Double {
        var low = 0.0, high = 1.0
        func fits(_ factor: Double) -> Bool {
            stops.allSatisfy { WCAGContrast.luminance($0.scaled(by: factor)) <= maxStopLuminance }
        }
        if fits(high) { return high }
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return low
    }

    // MARK: - Medal colors

    static let medalGold   = Color(red: 1.0,  green: 0.84, blue: 0.0)
    static let medalSilver = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let medalBronze = Color(red: 0.80, green: 0.50, blue: 0.20)
}
