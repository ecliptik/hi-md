import SwiftUI

struct WrappedIntroSlide: View {
    let year: Int
    let palette: [Color]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: MinidiscSpacing.xs) {
                    Text("YOUR")
                        .scaledFont(size: 16, weight: .heavy, design: .rounded)
                        .tracking(4)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))

                    Text("\(year)")
                        .scaledFont(size: 120, weight: .black, design: .rounded)
                        .kerning(-3)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text("Wrapped")
                        .scaledFont(size: 52, weight: .heavy, design: .rounded)
                        .kerning(-1)
                        .foregroundStyle(.white)
                }

                Spacer()
                Spacer()

                Text("Your year in music.")
                    .scaledFont(size: 18, weight: .medium, design: .rounded)
                    .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                    .padding(.bottom, MinidiscSpacing.xxxxl)
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
