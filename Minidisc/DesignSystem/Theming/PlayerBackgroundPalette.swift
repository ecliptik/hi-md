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

/// The Mac's full-screen lyrics backdrop: the cover's colours made vivid and much brighter than
/// the player's, with a soft dark wash behind the lyrics and behind the song's text so white
/// stays readable. Every number here is checked by the full-screen contrast tests.
enum FullScreenLyricsBackdrop {
    /// The brightest a vivid stop gets. White, the line being sung, keeps 3:1 on it with no wash.
    nonisolated static let maxLuminance = 0.28
    /// The wash behind the lyrics (and, with Reduce Transparency, over the whole backdrop): the
    /// line before or after the current one reaches 3:1 on it.
    nonisolated static let lyricsWashOpacity = 0.42
    /// The wash behind the title, the times and the controls: secondary text reaches 4.5:1.
    nonisolated static let textWashOpacity = 0.38
    /// The lines either side of the one being sung.
    nonisolated static let nearLineOpacity = 0.55

    /// The cover's colours, saturated and brightened, then darkened to `maxLuminance`. A grey
    /// sleeve takes a hint of `accent` first, as the Now Playing backdrop does.
    static func colors(from samples: [Color], accent: Color) -> [Color] {
        let accentRGB = WCAGContrast.RGB(accent.rgbComponents)
        return samples.enumerated().map { index, sample in
            guard let rgb = WCAGContrast.RGB(sample.rgbComponents) else { return .black }
            let fraction = Double(index) / Double(max(samples.count - 1, 1))
            let tinted = accentRGB.map { PlayerBackgroundPalette.tinted(rgb, toward: $0, fraction: fraction) } ?? rgb
            let stop = vivid(tinted)
            return Color(red: stop.red, green: stop.green, blue: stop.blue)
        }
    }

    /// `color` with its saturation raised and its brightness lifted to full, then darkened until
    /// its luminance is at most `maxLuminance`. The hue stays.
    nonisolated static func vivid(_ color: WCAGContrast.RGB) -> WCAGContrast.RGB {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let saturation = high > 0 ? (high - low) / high : 0
        let boosted = min(saturation * 1.35 + 0.08, 1)
        // Each component keeps its place between the lowest and the highest.
        func lifted(_ component: Double) -> Double {
            let place = high > low ? (component - low) / (high - low) : 1
            return 1 - boosted + boosted * place
        }
        var stop = WCAGContrast.RGB(red: lifted(color.red), green: lifted(color.green), blue: lifted(color.blue))
        while WCAGContrast.luminance(stop) > maxLuminance {
            stop = stop.scaled(by: 0.97)
        }
        return stop
    }
}
