import SwiftUI

/// The full player's backdrop, built from the cover's colour bands, and the white content drawn
/// over it. Every stop is darkened to `maxLuminance`, so the opacities below hold over any cover:
/// the worst case is a saturated red band, not a bright one (contrast sweep 2026-10-26).
enum PlayerBackgroundPalette {
    /// The brightest relative luminance a backdrop stop keeps. White reaches 7.5:1 on it.
    nonisolated static let maxLuminance = 0.09

    /// Secondary text and glyphs (artist, times, inactive toolbar icons). White at this opacity
    /// reaches 4.5:1 on every capped stop (4.86:1 worst); 0.7 fell to 4.1:1 on saturated reds.
    nonisolated static let secondaryOpacity = 0.78

    /// Large text and graphical objects that only need 3:1 (dimmed lyric lines, the grabber,
    /// reorder handles): 3.27:1 worst.
    nonisolated static let dimmedOpacity = 0.6

    static func colors(from samples: [Color]) -> [Color] {
        samples.enumerated().map { index, sample in
            guard let rgb = sample.rgbComponents else { return .black }
            let depth = 1 - 0.12 * Double(index) / Double(max(samples.count - 1, 1))
            let stop = capped(WCAGContrast.RGB(red: rgb.red, green: rgb.green, blue: rgb.blue), depth: depth)
            return Color(red: stop.red, green: stop.green, blue: stop.blue)
        }
    }

    /// The Mac players' backdrop: `colors(from:)`, except that a near-grey cover (a white,
    /// black or grey sleeve) takes a hint of `accent`, more at the top than the bottom, so it
    /// reads as a tinted gradient instead of flat grey. The stops are capped as before.
    static func tintedColors(from samples: [Color], accent: Color) -> [Color] {
        guard let accentRGB = WCAGContrast.RGB(accent.rgbComponents) else { return colors(from: samples) }
        return samples.enumerated().map { index, sample in
            guard let rgb = WCAGContrast.RGB(sample.rgbComponents) else { return .black }
            let fraction = Double(index) / Double(max(samples.count - 1, 1))
            let tinted = Self.tinted(rgb, toward: accentRGB, fraction: fraction)
            let stop = capped(tinted, depth: 1 - 0.12 * fraction)
            return Color(red: stop.red, green: stop.green, blue: stop.blue)
        }
    }

    /// Below this saturation a stop counts as grey.
    nonisolated static let neutralSaturation = 0.12

    /// `color` blended toward `accent` when it's nearly grey: 45% at the top stop (`fraction`
    /// 0) to 25% at the bottom one. Coloured stops are left alone.
    nonisolated static func tinted(_ color: WCAGContrast.RGB, toward accent: WCAGContrast.RGB,
                                   fraction: Double) -> WCAGContrast.RGB {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let saturation = high > 0 ? (high - low) / high : 0
        guard saturation < neutralSaturation else { return color }
        let amount = 0.45 - 0.2 * min(max(fraction, 0), 1)
        // A black sleeve has no brightness to tint, so it borrows some before blending.
        let base = high < 0.2 ? WCAGContrast.RGB(red: 0.35, green: 0.35, blue: 0.35) : color
        return WCAGContrast.RGB(red: base.red + (accent.red - base.red) * amount,
                                green: base.green + (accent.green - base.green) * amount,
                                blue: base.blue + (accent.blue - base.blue) * amount)
    }

    /// One backdrop stop: `color` scaled by `depth`, then darkened until its luminance is at most
    /// `maxLuminance`. Convex interpolation between such sRGB stops stays under the cap, so a
    /// light stripe cannot cross the controls.
    nonisolated static func capped(_ color: WCAGContrast.RGB, depth: Double = 1) -> WCAGContrast.RGB {
        var stop = color.scaled(by: depth)
        while WCAGContrast.luminance(stop) > maxLuminance {
            stop = stop.scaled(by: 0.96)
        }
        return stop
    }

    /// `color` darkened to the backdrop cap, for other surfaces that carry the player's white
    /// content over a cover colour (the mini player's tint, the artist information sheet).
    static func capped(_ color: Color) -> Color {
        guard let rgb = WCAGContrast.RGB(color.rgbComponents) else { return color }
        let stop = capped(rgb)
        return Color(red: stop.red, green: stop.green, blue: stop.blue)
    }

    static func luminance(red: Double, green: Double, blue: Double) -> Double {
        WCAGContrast.luminance(WCAGContrast.RGB(red: red, green: green, blue: blue))
    }
}
