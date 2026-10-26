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
