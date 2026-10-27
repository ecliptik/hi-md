import SwiftUI

/// How the lyric lines around the one being sung recede.
nonisolated enum LyricsLineDepth: Equatable, Sendable {
    /// Every other line dims alike: the iPhone player and the main window's panel.
    case dimmed
    /// A light depth of field: the Mac Now Playing view and MiniPlayer, which show many lines
    /// beside the player.
    case gentle
    /// A strong depth of field around one huge line: the Mac's full-screen lyrics, about four
    /// lines tall.
    case deep
}

/// The opacity and blur of a lyric line `distance` lines from the one being sung.
nonisolated struct LyricsLineAppearance: Equatable, Sendable {
    let opacity: Double
    let blur: Double

    /// Increase Contrast or Reduce Transparency (`prefersLegibility`): no blur, and every line
    /// keeps 3:1 over its backdrop. Otherwise the line next to the current one does too, and
    /// lines further out fade into the background.
    static func line(atDistance distance: Int, depth: LyricsLineDepth, prefersLegibility: Bool) -> LyricsLineAppearance {
        guard distance > 0 else { return LyricsLineAppearance(opacity: 1, blur: 0) }
        switch depth {
        case .dimmed:
            return LyricsLineAppearance(opacity: PlayerBackgroundPalette.dimmedOpacity, blur: 0)
        case .gentle:
            if prefersLegibility { return LyricsLineAppearance(opacity: PlayerBackgroundPalette.dimmedOpacity, blur: 0) }
            switch distance {
            case 1: return LyricsLineAppearance(opacity: PlayerBackgroundPalette.dimmedOpacity, blur: 0.8)
            case 2: return LyricsLineAppearance(opacity: 0.48, blur: 1.6)
            default: return LyricsLineAppearance(opacity: 0.38, blur: 2.4)
            }
        case .deep:
            if prefersLegibility {
                return LyricsLineAppearance(opacity: distance == 1 ? 0.6 : FullScreenLyricsBackdrop.nearLineOpacity, blur: 0)
            }
            switch distance {
            case 1: return LyricsLineAppearance(opacity: FullScreenLyricsBackdrop.nearLineOpacity, blur: 2.5)
            case 2: return LyricsLineAppearance(opacity: 0.32, blur: 5)
            default: return LyricsLineAppearance(opacity: 0.18, blur: 8)
            }
        }
    }
}

struct LyricsLineView: View {
    let value: String
    let index: Int
    let currentIndex: Int?
    let isSynced: Bool
    let isTappable: Bool
    let onTap: () -> Void
    /// Centred, larger lines for the full-screen karaoke view.
    var isKaraoke = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lyricsTypography) private var typography

    /// Increase Contrast or Reduce Transparency: no depth-of-field blur, and far lines no dimmer
    /// than the near ones.
    private var prefersLegibility: Bool { colorSchemeContrast == .increased || reduceTransparency }

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    private var appearance: LyricsLineAppearance {
        LyricsLineAppearance.line(atDistance: distance, depth: typography.depth, prefersLegibility: prefersLegibility)
    }

    /// Full screen keeps the strong depth-of-field; in the player, other lines dim, and on the
    /// Mac's Now Playing view they blur a little too.
    private var blurRadius: CGFloat {
        guard isSynced, currentIndex != nil else { return 0 }
        guard isKaraoke else { return appearance.blur }
        guard !prefersLegibility else { return 0 }
        switch distance {
        case 0: return 0
        case 1: return 1.5
        case 2: return 3.5
        default: return 6
        }
    }

    /// Every line is large bold text, so dimmed lines keep 3:1 over the worst backdrop. In the
    /// player they were 2.6:1 at 0.5; full screen, 2.5:1 and 1.8:1 at 0.4 and 0.25 (contrast
    /// sweep 2026-10-26, audit M3).
    private var opacity: Double {
        guard isSynced, currentIndex != nil else { return 1.0 }
        guard isKaraoke else { return appearance.opacity }
        if prefersLegibility { return distance == 0 ? 1.0 : 0.8 }
        switch distance {
        case 0: return 1.0
        case 1: return 0.8
        case 2: return 0.6
        default: return 0.5
        }
    }

    private var scale: CGFloat {
        guard isSynced, currentIndex != nil else { return 1.0 }
        return distance == 0 ? 1.05 : 1.0
    }

    private var lineFont: Font {
        if isKaraoke {
            return .system(.largeTitle, design: .rounded, weight: .heavy)
        }
        if let size = typography.lineSize { return .system(size: size, weight: .bold, design: .rounded) }
        return .system(.title2, design: .rounded, weight: .bold)
    }

    var body: some View {
        Text(value)
            .font(lineFont)
            .multilineTextAlignment(isKaraoke ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: isKaraoke ? .center : .leading)
            .foregroundStyle(.white.opacity(opacity))
            .blur(radius: blurRadius)
            .scaleEffect(isKaraoke && distance == 0 && currentIndex != nil ? 1.12 : scale,
                         anchor: isKaraoke ? .center : .leading)
            // Reduce Motion: the lines change at once, without the blur and size easing in.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: currentIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
            .accessibilityAddTraits(isTappable ? .isButton : [])
            .accessibilityHint(isTappable ? Text("Plays from this line") : Text(verbatim: ""))
            .accessibilityAction {
                if isTappable { onTap() }
            }
    }
}
