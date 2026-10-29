import SwiftUI

// MARK: - Spacing scale (4pt grid)

enum MinidiscSpacing {
    static let xs: CGFloat    = 4
    static let s: CGFloat     = 8
    static let m: CGFloat     = 12
    static let l: CGFloat     = 16   // default horizontal screen padding
    static let xl: CGFloat    = 20
    static let xxl: CGFloat   = 24   // between sections
    static let xxxl: CGFloat  = 32
    static let xxxxl: CGFloat = 48

    /// Bottom scroll margin reserved for the iOS tabViewBottomAccessory mini player,
    /// which floats over tab content without extending the safe area.
    static let miniPlayerBottomMargin: CGFloat = 80
}

// MARK: - Corner radius scale

enum MinidiscCornerRadius {
    static let xs: CGFloat       = 4
    static let s: CGFloat        = 6
    static let standard: CGFloat = 8    // all cover arts, most cards
    static let large: CGFloat     = 12   // full-player cover art, sheets
    static let hero: CGFloat      = 20   // Wrapped stat hero, year card
    static let pill: CGFloat      = 999  // capsule buttons
}

// MARK: - Shadow presets

enum MinidiscShadow {
    static let coverRadius: CGFloat  = 8
    static let coverY: CGFloat       = 4
    static let coverOpacity: Double  = 0.15
}

// MARK: - View modifier: content width

/// Keeps lists and detail screens at a readable width on iPad, the Mac and wide windows, centred
/// in the space; iPhones (compact width) are unchanged.
struct ContentWidthModifier: ViewModifier {
    static let maxReadableWidth: CGFloat = 760
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: Self.maxReadableWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func minidiscContentWidth() -> some View {
        modifier(ContentWidthModifier())
    }

    /// The iOS 26 scroll-edge effect (the soft blur under the status bar and top bar), held back
    /// until the page has scrolled `threshold` points. On the immersive detail pages the cover scrolls
    /// under a transparent bar, where the blur would flicker in and out over the artwork; past it,
    /// the songs would otherwise run under the clock with nothing behind it.
    func minidiscTopScrollEdgeEffect(afterScrolling threshold: CGFloat = 280) -> some View {
        modifier(TopScrollEdgeEffectAfterHeader(threshold: threshold))
    }
}

private struct TopScrollEdgeEffectAfterHeader: ViewModifier {
    let threshold: CGFloat
    @State private var isPastHeader = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > threshold
            } action: { _, isPast in
                isPastHeader = isPast
            }
            .scrollEdgeEffectHidden(!isPastHeader, for: .top)
    }
}

// MARK: - View modifier: cover art style

struct MinidiscCoverModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.minidiscCoverBorder, lineWidth: 1)
                }
            }
    }
}

extension View {
    func minidiscCoverStyle(cornerRadius: CGFloat = MinidiscCornerRadius.standard) -> some View {
        modifier(MinidiscCoverModifier(cornerRadius: cornerRadius))
    }
}
