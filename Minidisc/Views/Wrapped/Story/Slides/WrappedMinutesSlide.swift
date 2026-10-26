import SwiftUI

struct WrappedMinutesSlide: View {
    let data: WrappedData
    let palette: [Color]

    @State private var animatedSeconds: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalHours: Int { Int(data.totalSecondsListened / 3600) }

    var body: some View {
        ZStack {
            MeshGradientBackground(palette: palette, animated: !reduceMotion)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text("This year, you")
                        .scaledFont(size: 22, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                    Text("listened to")
                        .scaledFont(size: 22, weight: .medium, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                }

                Spacer(minLength: MinidiscSpacing.xl)

                AnimatedMinutesText(seconds: animatedSeconds)

                Spacer(minLength: MinidiscSpacing.xl)

                if totalHours > 0 {
                    Text("That's \(totalHours) hours of music.")
                        .scaledFont(size: 20, weight: .semibold, design: .rounded)
                        .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
                }

                Spacer()
            }
            .padding(.horizontal, MinidiscSpacing.xl)
            .wrappedSlideEntrance()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { triggerAnimation() }
    }

    private func triggerAnimation() {
        if reduceMotion {
            animatedSeconds = data.totalSecondsListened
            return
        }
        animatedSeconds = 0
        withAnimation(.spring(response: 1.4, dampingFraction: 0.85).delay(0.2)) {
            animatedSeconds = data.totalSecondsListened
        }
    }
}

private struct AnimatedMinutesText: View, Animatable {
    var seconds: Double

    var animatableData: Double {
        get { seconds }
        set { seconds = newValue }
    }

    var body: some View {
        let (number, unit) = seconds.wrappedHeroMinutesFormat()
        VStack(alignment: .leading, spacing: MinidiscSpacing.xs) {
            Text(number)
                .scaledFont(size: 96, weight: .black, design: .rounded)
                .kerning(-2)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(unit)
                .scaledFont(size: 24, weight: .medium, design: .rounded)
                .foregroundStyle(.white.opacity(WrappedYearPalette.secondaryTextOpacity))
        }
    }
}
