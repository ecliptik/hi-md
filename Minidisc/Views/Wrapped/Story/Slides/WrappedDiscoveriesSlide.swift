import SwiftUI

struct WrappedDiscoveriesSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)

                Text("DISCOVERIES")
                    .scaledFont(size: 13, weight: .heavy, design: .rounded)
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("You explored")
                        .scaledFont(size: 26, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                    Text("your library.")
                        .scaledFont(size: 26, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                }

                Spacer(minLength: MinidiscSpacing.xl)

                VStack(alignment: .leading, spacing: MinidiscSpacing.m) {
                    discoveryRow(count: data.totalUniqueTracks, label: "different songs")
                    discoveryRow(count: data.totalUniqueArtists, label: "different artists")
                    discoveryRow(count: data.totalUniqueAlbums, label: "different albums")
                }

                Spacer()
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func discoveryRow(count: Int, label: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MinidiscSpacing.s) {
            Text("\(count)")
                .scaledFont(size: 48, weight: .black, design: .rounded)
                .kerning(-1)
                .foregroundStyle(.white)
            Text(label)
                .scaledFont(size: 20, weight: .medium, design: .rounded)
                .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
        }
    }
}
