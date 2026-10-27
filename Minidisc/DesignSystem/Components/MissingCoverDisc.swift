import SwiftUI

/// The MiniDisc standing in for a missing album, song or playlist cover: a still disc on the same
/// neutral tile a cover shows while it loads, so the change from loading to missing only adds the
/// disc. Shaped like a cover by whoever clips it. Decorative: the item's title labels it.
struct MissingCoverDisc: View {
    var cornerRadius: CGFloat = 0
    /// Large covers (an album's header) draw the full-resolution logo; rows and grids the thumbnail.
    var isLarge = false

    /// The loading tile's fill, which the disc sits on.
    static let tileFill = Color.primary.opacity(0.08)
    /// The disc's share of the tile, leaving a margin like a cover's border.
    static let discScale: CGFloat = 0.84

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Self.tileFill)
            Group {
                if isLarge {
                    MinidiscLogoView()
                } else {
                    Image(.minidiscLogoThumb)
                        .resizable()
                        .scaledToFit()
                }
            }
            .scaleEffect(Self.discScale)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        }
        .accessibilityHidden(true)
    }
}
