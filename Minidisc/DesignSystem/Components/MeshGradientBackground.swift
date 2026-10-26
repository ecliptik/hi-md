import SwiftUI

struct MeshGradientBackground: View {
    /// 3 colors from WrappedYearPalette, already darkened so white text on them reaches 4.5:1.
    /// The mesh blends between them; the stops stop a little short of the 4.5:1 limit to leave
    /// room for any overshoot from its smoothed colour interpolation.
    let palette: [Color]
    let animated: Bool

    @Environment(\.systemPrefersReducedResourceUsage) private var prefersReducedResourceUsage
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        gradient
            .onAppear { updateAnimation() }
            .onChange(of: prefersReducedResourceUsage) { updateAnimation() }
    }

    /// Drifts slowly unless motion is reduced or iOS asks apps to save resources.
    private func updateAnimation() {
        guard animated, !prefersReducedResourceUsage else {
            // A non-animated change replaces the repeating animation.
            withTransaction(Transaction(animation: nil)) { animationPhase = 0 }
            return
        }
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            animationPhase = 1
        }
    }

    private var gradient: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: currentPoints,
            colors: distributedColors
        )
    }

    private var currentPoints: [SIMD2<Float>] {
        let p = Float(animationPhase)
        return [
            [0.0, 0.0], [0.5 + 0.04 * p, 0.0],                        [1.0, 0.0],
            [0.0, 0.5 + 0.03 * p], [0.5 - 0.04 * p, 0.5 + 0.04 * p], [1.0, 0.5 - 0.03 * p],
            [0.0, 1.0], [0.5 + 0.03 * p, 1.0],                        [1.0, 1.0]
        ]
    }

    private var distributedColors: [Color] {
        guard palette.count >= 3 else {
            return Array(repeating: palette.first ?? .clear, count: 9)
        }
        let c0 = palette[0], c1 = palette[1], c2 = palette[2]
        return [c0, c0, c1,
                c0, c1, c1,
                c1, c2, c2]
    }
}
