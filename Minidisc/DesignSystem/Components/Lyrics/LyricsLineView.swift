import SwiftUI

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
    @Environment(\.lyricsTypography) private var typography

    /// Increase Contrast or Reduce Transparency: no depth-of-field blur, and far lines no dimmer
    /// than the near ones.
    private var prefersLegibility: Bool { colorSchemeContrast == .increased || reduceTransparency }

    private var distance: Int {
        guard let currentIndex else { return 0 }
        return abs(index - currentIndex)
    }

    /// Full screen keeps the strong depth-of-field; in the player, other lines only dim, so the lyrics
    /// stay legible next to the controls.
    private var blurRadius: CGFloat {
        guard isKaraoke, isSynced, currentIndex != nil, !prefersLegibility else { return 0 }
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
        guard isKaraoke else { return distance == 0 ? 1.0 : PlayerBackgroundPalette.dimmedOpacity }
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
        if isKaraoke { return .system(.largeTitle, design: .rounded, weight: .heavy) }
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
            .animation(.easeInOut(duration: 0.25), value: currentIndex)
            .contentShape(Rectangle())
            .onTapGesture {
                if isTappable { onTap() }
            }
    }
}
