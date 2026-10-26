import SwiftUI

struct WrappedTopGenreSlide: View {
    let data: WrappedData
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: MinidiscSpacing.xxxxl)

                Text("YOUR SOUND")
                    .scaledFont(size: 13, weight: .heavy, design: .rounded)
                    .tracking(2.5)
                    .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Your most-played")
                        .scaledFont(size: 22, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                    Text("genre was")
                        .scaledFont(size: 22, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                }

                Spacer(minLength: MinidiscSpacing.l)

                Text(data.dominantGenre ?? "Mixed")
                    .scaledFont(size: 64, weight: .black, design: .rounded)
                    .kerning(-1.5)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)

                Spacer()
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
