import Foundation

/// Picks black or white content for a background taken from a cover, and the opacity its secondary
/// text needs, by WCAG contrast rather than perceived brightness (contrast sweep 2026-10-26).
///
/// The cover-colour screens used to switch to black text only above a perceived brightness of
/// 0.6, which left white text at 1.4:1 on bright greens and yellows, and their 70% secondary
/// text below 4.5:1 on most mid tones.
nonisolated enum ReadableContent {
    nonisolated struct Resolution: Equatable, Sendable {
        /// The background stops, adjusted only when neither black nor white reached 4.5:1.
        var backgrounds: [WCAGContrast.RGB]
        var usesDarkContent: Bool
        /// The lowest opacity, from the preferred one up to 1, at which secondary text in the
        /// content colour reaches 4.5:1 on every stop.
        var secondaryOpacity: Double

        var content: WCAGContrast.RGB { usesDarkContent ? .black : .white }
    }

    static let minimumRatio = 4.5

    /// - Parameters:
    ///   - backgrounds: the stops the content sits on (one colour, or a gradient's ends).
    ///   - preferredSecondaryOpacity: the design's secondary opacity, kept where it already passes.
    static func resolve(backgrounds: [WCAGContrast.RGB], preferredSecondaryOpacity: Double = 0.7) -> Resolution {
        precondition(!backgrounds.isEmpty)
        let white = worstRatio(.white, on: backgrounds)
        let black = worstRatio(.black, on: backgrounds)
        let usesDarkContent = black > white
        var stops = backgrounds
        if max(white, black) < minimumRatio {
            // Mid tones: move the stops just far enough from the content for 4.5:1, darker under
            // white text, lighter under black.
            stops = usesDarkContent ? lightened(backgrounds) : darkened(backgrounds)
        }
        let content: WCAGContrast.RGB = usesDarkContent ? .black : .white
        return Resolution(backgrounds: stops, usesDarkContent: usesDarkContent,
                          secondaryOpacity: secondaryOpacity(content, on: stops, preferred: preferredSecondaryOpacity))
    }

    static func worstRatio(_ content: WCAGContrast.RGB, on backgrounds: [WCAGContrast.RGB],
                           opacity: Double = 1) -> Double {
        backgrounds.map { WCAGContrast.ratio(content.composited(over: $0, opacity: opacity), $0) }.min() ?? 21
    }

    static func secondaryOpacity(_ content: WCAGContrast.RGB, on backgrounds: [WCAGContrast.RGB],
                                 preferred: Double) -> Double {
        if worstRatio(content, on: backgrounds, opacity: preferred) >= minimumRatio { return preferred }
        guard worstRatio(content, on: backgrounds) >= minimumRatio else { return 1 }
        var low = preferred, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if worstRatio(content, on: backgrounds, opacity: mid) >= minimumRatio { high = mid } else { low = mid }
        }
        // Round up to a whole percent so the stored value is tidy and still passes.
        return min(1, (high * 100).rounded(.up) / 100)
    }

    /// The largest scale (at most 1) that gives white 4.5:1 on every stop, with a little margin.
    private static func darkened(_ stops: [WCAGContrast.RGB]) -> [WCAGContrast.RGB] {
        let factor = search { factor in worstRatio(.white, on: stops.map { $0.scaled(by: factor) }) >= minimumRatio + 0.05 }
        return stops.map { $0.scaled(by: factor) }
    }

    /// The smallest mix towards white that gives black 4.5:1 on every stop, with a little margin.
    private static func lightened(_ stops: [WCAGContrast.RGB]) -> [WCAGContrast.RGB] {
        func mixed(_ amount: Double) -> [WCAGContrast.RGB] {
            stops.map { WCAGContrast.RGB.white.composited(over: $0, opacity: amount) }
        }
        // `search` finds the largest passing value of a predicate that holds below a threshold,
        // so search over 1 - amount.
        let keep = search { keep in worstRatio(.black, on: mixed(1 - keep)) >= minimumRatio + 0.05 }
        return mixed(1 - keep)
    }

    /// The largest x in 0...1 for which `passes` holds, assuming it holds at 0 and stops holding
    /// at some point.
    private static func search(_ passes: (Double) -> Bool) -> Double {
        if passes(1) { return 1 }
        var low = 0.0, high = 1.0
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if passes(mid) { low = mid } else { high = mid }
        }
        return low
    }
}

nonisolated extension WCAGContrast.RGB {
    init?(_ components: (red: Double, green: Double, blue: Double)?) {
        guard let components else { return nil }
        self.init(red: components.red, green: components.green, blue: components.blue)
    }
}
