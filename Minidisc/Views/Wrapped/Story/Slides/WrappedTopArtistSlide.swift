import SwiftUI

struct WrappedTopArtistSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var topArtist: TopArtistEntry? { data.topArtists.first }

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)

                Text("TOP ARTIST")
                    .scaledFont(size: 13, weight: .heavy, design: .rounded)
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))

                Spacer()

                if let artist = topArtist {
                    Text(artist.name)
                        .scaledFont(size: 60, weight: .black, design: .rounded)
                        .kerning(-1.5)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)

                    Spacer(minLength: MinidiscSpacing.l)

                    HStack(spacing: MinidiscSpacing.s) {
                        statBadge(artist.playCount.plural("play", "plays"))
                        statBadge(artist.uniqueTracks.plural("track", "tracks"))
                    }
                } else {
                    Text("No artist data yet")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                }

                Spacer()
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBadge(_ text: String) -> some View {
        Text(text)
            .scaledFont(size: 15, weight: .semibold, design: .rounded)
            .foregroundStyle(.white)
            .padding(.horizontal, MinidiscSpacing.m)
            .padding(.vertical, MinidiscSpacing.s)
            .background(Color.white.opacity(WrappedYearPalette.chipFillOpacity), in: Capsule())
    }
}
